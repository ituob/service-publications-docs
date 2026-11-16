#!/usr/bin/env ruby
# frozen_string_literal: true

# Compares a generated Service Publication PDF against the official ITU PDF.
#
#   ruby scripts/compare_official_pdf.rb GENERATED.pdf OFFICIAL.pdf \
#        [--out DIR] [--data data.yaml] [--dispositions dispositions.yaml]
#
# Both PDFs go through `pdftotext -layout`. Two layers are compared:
#   rows  - telegraph-office table rows (office name + office code), in order
#   prose - the preface words between "Note from TSB" and the first table header
# Every delta is printed with a disposition (data, layout, bug). The tool only
# settles what a measurement can settle; a human disposition lives in the
# checked-in --dispositions file (matched on the exact delta text, so a stale
# entry is an error). Anything left over is "unreviewed". The exit status is
# non-zero while any bug, unreviewed delta or stale disposition remains: 1 for
# an open delta, 2 for a usage or config error (bad option, unreadable file,
# malformed dispositions).
require 'open3'
require 'optparse'
require 'set'
require 'yaml'

module OfficialPdfComparison
  CODE = /\A(?=.*[A-Z])[A-Z0-9-]{4}\z/
  FURNITURE = /\A\s*Annex to ITU OB|\A\s*Service Publication Annex|\A\s*ITUPublications/
  TABLE_HEADER = %r{Country\s*/\s*(?:[Gg]eographical|Network)}
  LIST_MARKER = /\A\s*(?:\d+\.|[a-z]\))\s+/

  FOOTNOTE = /\A(?:\d+|[a-z])\)\z/
  COLUMN_SLACK = 4
  MAX_SCAN = 6
  DISPOSITIONS = %w[data layout bug].freeze

  # Bad command line, unreadable input or a malformed dispositions file: exit 2.
  class UsageError < StandardError; end

  # The lines between two code lines (or between a code line and page
  # furniture) that can be wrap text of one row's name. Each line carries the
  # text it has at the upper row's name column (a) and at the lower row's (b),
  # nil where it does not continue that column. A gap is split between its two
  # rows: the upper row takes the first s lines, the lower row the rest, so a
  # line belongs to exactly one row and none is dropped. valid lists the splits
  # the columns allow.
  Gap = Struct.new(:lines) do
    def valid
      @valid ||= (0..lines.size).select { |s| lines.first(s).all? { |l| l[:a] } && lines.drop(s).all? { |l| l[:b] } }
    end

    def all_text = lines.map { |l| l[:a] || l[:b] }
  end

  # A table row: the code line's name and the gaps above and below it. How a gap
  # is split between its two rows differs between the two PDFs (and a name's
  # first line may sit above or below the code), so a row has one reading of
  # its name per split of its two gaps: the lines it takes above, the code-line
  # text, the lines it takes below, joined. Which split is the right one is
  # settled across rows, see OfficialPdfComparison.consistent_failures.
  Row = Struct.new(:name, :code, :line, :col, :above, :below) do
    def to_s = "#{code} #{name}"

    # Every wrap line of the row's neighbourhood, in reading order.
    def full_name = OfficialPdfComparison.squish((above.all_text + [name] + below.all_text).join(' '))

    def reading(sa, sb)
      OfficialPdfComparison.normalise((above.lines.drop(sa).map { |l| l[:b] } + [name] + below.lines.first(sb).map { |l| l[:a] }).join(' '))
    end

    def splits = above.valid.product(below.valid)

    def readings = @readings ||= splits.map { |sa, sb| reading(sa, sb) }.to_set

    def same_name?(other) = readings.intersect?(other.readings)
  end
  Delta = Struct.new(:layer, :side, :text, :disposition, :reason, :manual)

  module_function

  def pdf_text(path)
    out, err, st = Open3.capture3('pdftotext', '-layout', path, '-')
  rescue SystemCallError => e
    raise UsageError, "cannot run pdftotext: #{e.message}"
  else
    raise UsageError, "pdftotext failed for #{path}: #{err.lines.first.to_s.strip}" unless st.success?

    out
  end

  def squish(str)
    str.gsub(/[‘’]/, "'").gsub(/[“”]/, '"').gsub(/[ \s]+/, ' ').strip
  end

  def normalise(str)
    squish(str).downcase.gsub(/[^[:alnum:]]+/, ' ').strip
  end

  # Rows: a layout line ending in a 4-char office code. The name is whatever
  # precedes the code in its cell, or the previous cell when the code stands
  # alone. Wrapped names continue on neighbouring lines in the same column;
  # they are kept as fragments (see Row).
  def cells_at(line)
    line.rstrip.to_enum(:scan, /\S+(?: \S+)*/).map { [Regexp.last_match[0], Regexp.last_match.begin(0)] }
  end

  def rows(text)
    lines = text.lines.map { |l| l.delete("\f") }
    found = {}
    lines.each_with_index do |line, i|
      cells = cells_at(line)
      next if line =~ FURNITURE || cells.empty?

      m = cells.last[0].match(/(?:\A|\s)((?=[A-Z0-9-]*[A-Z])[A-Z0-9-]{4})(?:\d\)|[a-z]\)?|\*)?\z/)
      next unless m
      next if cells.size == 1 && (m.pre_match.empty? || line[/\A */].size < 20)

      name, col = m.pre_match.empty? ? cells[-2] : [m.pre_match, cells.last[1]]
      found[i] = [squish(name), m[1], col]
    end
    above, below = build_gaps(lines, found)
    found.each_with_index.map do |(i, (name, code, col)), k|
      Row.new(name, code, i + 1, col, above[k], below[k])
    end
  end

  # The gap above and the gap below each row. Two rows with no page furniture or
  # table header between them share the gap between them; a barrier splits it
  # into a trailing gap of the upper row and a leading gap of the lower. Lines
  # more than MAX_SCAN from the row (or rows) they continue are not wrap text.
  def build_gaps(lines, found)
    barriers = header_blocks(lines)
    barrier = ->(j) { lines[j] =~ FURNITURE || barriers.include?(j) }
    idx = found.keys
    above = Array.new(idx.size)
    below = Array.new(idx.size)
    (0..idx.size).each do |k|
      up = idx[k - 1] if k.positive?
      low = idx[k] if k < idx.size
      if up && low && ((up + 1)...low).none? { |j| barrier.call(j) }
        below[k - 1] = above[k] = Gap.new(shared_lines(lines, found, up, low))
      else
        above[k] = Gap.new(edge_lines(lines, found, barrier, low, -1)) if low
        below[k - 1] = Gap.new(edge_lines(lines, found, barrier, up, 1)) if up
      end
    end
    [above, below]
  end

  # Lines between code lines up and low. A cell on a code line itself counts
  # too when it sits at the other row's name column (a name line that shares its
  # line with the next or previous row's code).
  def shared_lines(lines, found, up, low)
    col_up = found[up][2]
    col_low = found[low][2]
    out = foreign_cells(lines, up, found[up]).filter_map { |cells| gap_line(cells, nil, col_low) }
    ((up + 1)...low).each do |j|
      next unless j - up <= MAX_SCAN || low - j <= MAX_SCAN

      out << gap_line(name_cells(lines[j]), col_up, col_low)
    end
    foreign = foreign_cells(lines, low, found[low]).filter_map { |cells| gap_line(cells, col_up, nil) }
    out.compact + foreign + continuation_lines(lines, found, low, col_up, foreign.any?)
  end

  # A name that continues under the lower row's code line (the upper row's name
  # column holds a different cell there): the following lines at that column,
  # up to the first line that has none or is a code line.
  def continuation_lines(lines, found, low, col, started)
    out = []
    j = low + 1
    while started && j < lines.size && (j - low) <= MAX_SCAN && !found.key?(j) && lines[j] !~ FURNITURE
      line = gap_line(name_cells(lines[j]), col, nil) or break
      out << line
      j += 1
    end
    out
  end

  # Lines on one side of a row only (up to a barrier or MAX_SCAN lines): dir 1
  # below the row (a trailing gap), -1 above it (a leading gap).
  def edge_lines(lines, found, barrier, row, dir)
    col = found[row][2]
    out = []
    j = row + dir
    while (j - row).abs <= MAX_SCAN && j >= 0 && j < lines.size && !barrier.call(j) && !found.key?(j)
      out << gap_line(name_cells(lines[j]), dir == 1 ? col : nil, dir == 1 ? nil : col)
      j += dir
    end
    out = out.reverse if dir == -1
    out.compact
  end

  # {a: text at the upper row's column, b: at the lower row's}; nil when it
  # continues neither.
  def gap_line(cells, col_up, col_low)
    a = col_up && column_text(cells, col_up)
    b = col_low && column_text(cells, col_low)
    { a: a, b: b } if a || b
  end

  # The cells of a code line other than its name and code, as one cell list
  # per cell, so each can be tested against the neighbouring row's column.
  def foreign_cells(lines, i, (_, _, col))
    cells = name_cells(lines[i])
    code_col = cells_at(lines[i]).last[1]
    cells.reject { |_, c| c == code_col || (c - col).abs <= COLUMN_SLACK }.map { |cell| [cell] }
  end

  def header_blocks(lines)
    lines.each_index.with_object(Set.new) do |i, set|
      next unless lines[i] =~ TABLE_HEADER

      stop = (i...[i + MAX_SCAN, lines.size].min).find { |k| lines[k] =~ /\A\s*1\s+2\s+3\s+4\s+5\s*\z/ } || i
      set.merge(i..stop)
    end
  end

  def name_cells(line) = cells_at(line).reject { |t, _| t =~ FOOTNOTE }

  def column_text(cells, col)
    here = cells.select { |_, c| (c - col).abs <= COLUMN_SLACK }
    squish(here.map(&:first).join(' ')) unless here.empty?
  end

  def prose_words(text)
    lines = text.lines
    start = lines.index { |l| l.strip == 'Note from TSB' } || 0
    stop = lines.index.with_index { |l, i| i > start && l =~ TABLE_HEADER } || lines.size
    lines[start...stop]
      .reject { |l| l =~ FURNITURE || l.strip =~ /\A[–-]\s*\d+\s*[–-]\z/ }
      .map { |l| l.sub(LIST_MARKER, '') }
      .join(' ').then { |s| squish(s) }.split(' ')
  end

  # Longest common subsequence diff; returns [[:eq|:del|:ins, a, b], ...].
  # Items are equal when their keys are (default: themselves) or, if given,
  # when eq.call(x, y) is true.
  def diff(a, b, eq: nil, &key)
    unless eq
      key ||= :itself.to_proc
      ka = a.map(&key)
      kb = b.map(&key)
      eq = ->(x, y) { ka[x] == kb[y] }
      indexed = true
    end
    same = indexed ? eq : ->(i, j) { eq.call(a[i], b[j]) }
    n = a.size
    m = b.size
    t = Array.new(n + 1) { Array.new(m + 1, 0) }
    (n - 1).downto(0) do |i|
      (m - 1).downto(0) do |j|
        t[i][j] = same.call(i, j) ? t[i + 1][j + 1] + 1 : [t[i + 1][j], t[i][j + 1]].max
      end
    end
    ops = []
    i = j = 0
    while i < n && j < m
      if same.call(i, j)
        ops << [:eq, a[i], b[j]]
        i += 1
        j += 1
      elsif t[i + 1][j] >= t[i][j + 1]
        ops << [:del, a[i], nil]
        i += 1
      else
        ops << [:ins, nil, b[j]]
        j += 1
      end
    end
    ops.concat(a[i..].map { |x| [:del, x, nil] }) if i < n
    ops.concat(b[j..].map { |x| [:ins, nil, x] }) if j < m
    ops
  end

  # Collapse consecutive del/ins ops into hunks of {generated:, official:}.
  def hunks(ops)
    out = []
    cur = nil
    ops.each do |op, a, b|
      if op == :eq
        cur = nil
        next
      end
      cur ||= out.push({ generated: [], official: [] }).last
      cur[:generated] << a if op == :del
      cur[:official] << b if op == :ins
    end
    out
  end

  # generated is side A, official is side B. Rows align on code AND name, so a
  # dropped row inside a run of repeated codes is the row reported. What does
  # not align is paired by code alone: same code, different name.
  def compare_rows(generated_rows, official_rows, dataset_index = nil, generated_text = '', official_text = '')
    ops = diff(generated_rows, official_rows, eq: ->(g, o) { g.code == o.code && g.same_name?(o) })
    official_norm = " #{normalise(official_text)} "
    deltas = hunks(ops).flat_map { |h| classify_row_hunk(h, official_norm, official_rows) }
    deltas.concat(name_deltas(ops))
    deltas.each { |d| disposition_from_dataset(d, dataset_index) } if dataset_index
    deltas.concat(unrendered_deltas(generated_rows, dataset_index, generated_text)) if dataset_index
    [ops.count { |o, *| o == :eq }, deltas]
  end

  # Rows that aligned (some reading of each name is equal): a bug when no single
  # split of the shared wrap lines makes all aligned names equal at once
  # (see consistent_failures), a layout delta when the code-line names differ
  # only because the name wraps differently.
  def name_deltas(ops)
    pairs = ops.filter_map { |op, gen, off| [gen, off] if op == :eq }
    failed = consistent_failures(pairs)
    pairs.filter_map do |gen, off|
      if failed.include?([gen, off])
        Delta.new(:rows, :both, pair_text(gen, off), :bug, 'wrap lines cannot be split between the rows so that all names match (a wrap line is dropped, doubled or borrowed)')
      elsif normalise(gen.name) != normalise(off.name)
        Delta.new(:rows, :both, pair_text(gen, off), :layout, 'name wrapped across lines; the joined lines are equal')
      end
    end
  end

  # Each wrap line belongs to exactly one row, so the split of a gap chosen for
  # the row above must be the split the row below uses. Aligned pairs are
  # walked in order; a gap shared by two consecutive rows of a side ties their
  # choices (a gap next to an unaligned row is free on that side). Returns the
  # pairs for which no consistent choice exists; the walk restarts after each.
  def consistent_failures(pairs)
    failed = []
    prev = nil
    reach = nil
    pairs.each do |gen, off|
      tied_g = prev && prev[0].below.equal?(gen.above)
      tied_o = prev && prev[1].below.equal?(off.above)
      options = gen.splits.product(off.splits).select { |(ga, gb), (oa, ob)| gen.reading(ga, gb) == off.reading(oa, ob) }
      kept = options.select { |(ga, _), (oa, _)| reach.nil? || reach_ok?(reach, ga, oa, tied_g, tied_o) }
      if kept.empty?
        failed << [gen, off]
        kept = options
      end
      reach = kept.map { |(_, gb), (_, ob)| [gb, ob] }.uniq
      prev = [gen, off]
    end
    failed
  end

  # reach holds the [gen split, official split] pairs the previous aligned pair
  # allows for its lower gap; a tied side must continue one of them, on that
  # same pair of choices.
  def reach_ok?(reach, ga, oa, tied_g, tied_o)
    reach.any? { |g, o| (!tied_g || g == ga) && (!tied_o || o == oa) }
  end

  def pair_text(gen, off)
    "#{gen.code}: generated #{gen.full_name.inspect} vs official #{off.full_name.inspect}"
  end

  def classify_row_hunk(hunk, official_norm, official_rows)
    row_ops = diff(hunk[:generated], hunk[:official], eq: ->(g, o) { g.code == o.code })
    row_ops.map do |op, gen, off|
      case op
      when :eq then pair_delta(gen, off)
      when :ins then Delta.new(:rows, :official_only, off.to_s, :unreviewed, nil)
      else generated_only_delta(gen, official_norm, official_rows)
      end
    end
  end

  # A row only the generated PDF has is a bug unless the official PDF carries
  # the same text without it being a table row there (wrapped text that merely
  # looks like a row). A row the official PDF has elsewhere is out of order or
  # duplicated: a bug.
  def generated_only_delta(row, official_norm, official_rows)
    if official_rows.any? { |o| o.code == row.code && o.same_name?(row) }
      Delta.new(:rows, :generated_only, row.to_s, :bug, 'row is in the official PDF too, but not at this position (out of order or duplicated)')
    elsif official_norm.include?(" #{normalise("#{row.name} #{row.code}")} ")
      Delta.new(:rows, :generated_only, row.to_s, :layout, 'text is in the official PDF but not as a table row there')
    else
      Delta.new(:rows, :generated_only, row.to_s, :bug, 'row is in the generated PDF but its text is not in the official PDF')
    end
  end

  # With the dataset in hand a missing or extra row can be settled by
  # measurement instead of by eye. Codes are not unique (the "--XX" codes are
  # reused), so a row counts as "in the dataset" only when the code AND a
  # name (any language, either side a prefix of the other) are there.
  def in_dataset?(index, row_text)
    code, name = row_text.split(' ', 2)
    wanted = normalise(name.to_s)
    index.fetch(code, []).count { |names| names.any? { |n| n.start_with?(wanted) || wanted.start_with?(n) } }
  end

  def disposition_from_dataset(delta, index)
    return unless delta.layer == :rows && delta.disposition == :unreviewed

    matches = in_dataset?(index, delta.text)
    in_data = matches.positive?
    case delta.side
    when :official_only
      if matches > 1
        delta.reason = 'code and name occur more than once in the dataset; settle by hand'
      elsif in_data
        delta.disposition = :bug
        delta.reason = 'code and name are in the dataset but absent from the generated PDF'
      else
        delta.disposition = :data
        delta.reason = 'not in the dataset, so the generated PDF cannot contain it'
      end
    end
  end

  # Dataset codes that never reach the generated PDF: a build defect.
  # A code that appears elsewhere in the text (e.g. inside a cell note) is
  # rendered, just not as a table row.
  def unrendered_deltas(generated_rows, codes, generated_text)
    rendered = generated_rows.map(&:code).to_set
    (codes.keys - rendered.to_a).sort.reject { |c| generated_text.include?(c) }.map do |c|
      Delta.new(:rows, :dataset_only, c, :bug, 'office code is in the dataset but not rendered in the generated PDF')
    end
  end

  def dataset_index(path)
    YAML.safe_load_file(path).each_with_object(Hash.new { |h, k| h[k] = [] }) do |r, idx|
      next unless r['office_code']

      idx[r['office_code']] << (r['telegraph_office_name'] || {}).values.map { |n| normalise(n) }
    end
  end

  # Same code on both sides. The delta text carries both FULL names (every wrap
  # line), so a disposition that names it pins the whole row on both sides. The
  # names are the same text only when the full readings are equal (see Row), so
  # every pair that reaches here differs: a name that gained, lost or borrowed
  # a word is a bug, not a wrap.
  def pair_delta(gen, off)
    Delta.new(:rows, :both, pair_text(gen, off), :bug, 'same code, different name')
  end

  def compare_prose(generated_words, official_words)
    ops = diff(generated_words, official_words) { |w| normalise(w) }
    deltas = hunks(ops).map do |h|
      gen = h[:generated].join(' ')
      off = h[:official].join(' ')
      if normalise(gen) == normalise(off)
        Delta.new(:prose, :both, "generated #{gen.inspect} vs official #{off.inspect}", :layout,
                  'spacing/punctuation only')
      else
        Delta.new(:prose, :both, "generated #{gen.inspect} vs official #{off.inspect}", :unreviewed, nil)
      end
    end
    [ops.count { |o, *| o == :eq }, deltas]
  end

  # Human dispositions: a YAML list of {layer, side, text, disposition, reason,
  # count (default 1)}. An entry settles the bug/unreviewed deltas whose layer,
  # side and exact text it names; a reason is required, and an entry that does
  # not match exactly `count` such deltas is stale. Returns the problems.
  def apply_dispositions(deltas, entries)
    entries.flat_map do |e|
      problems = []
      problems << "disposition #{e['text'].inspect}: needs a reason" if e['reason'].to_s.strip.empty?
      problems << "disposition #{e['text'].inspect}: #{e['disposition'].inspect} is not data/layout/bug" unless DISPOSITIONS.include?(e['disposition'])
      hits = deltas.select do |d|
        %i[bug unreviewed].include?(d.disposition) && !d.manual &&
          [d.layer.to_s, d.side.to_s, d.text] == [e['layer'], e['side'], e['text']]
      end
      want = e.fetch('count', 1)
      if hits.size != want
        problems << "stale disposition #{e['text'].inspect}: matches #{hits.size} open deltas, expected #{want}"
      elsif problems.empty?
        hits.each do |d|
          d.disposition = e['disposition'].to_sym
          d.reason = e['reason']
          d.manual = true
        end
      end
      problems
    end
  end

  # Reads and validates the dispositions file: a YAML list of mappings with the
  # string keys layer, side, text, and an integer count if present.
  def load_dispositions(path)
    entries = YAML.safe_load_file(path)
    raise UsageError, "#{path}: dispositions must be a YAML list of mappings" unless entries.is_a?(Array) && entries.all?(Hash)

    entries.each_with_index do |e, i|
      missing = %w[layer side text].reject { |k| e[k].is_a?(String) }
      raise UsageError, "#{path}: entry #{i + 1} needs string #{missing.join(', ')}" unless missing.empty?
      raise UsageError, "#{path}: entry #{i + 1} count must be a positive integer" unless e.fetch('count', 1).is_a?(Integer) && e.fetch('count', 1).positive?
    end
    entries
  rescue Errno::ENOENT, Psych::Exception => e
    raise UsageError, "#{path}: #{e.message.lines.first.to_s.strip}"
  end

  def run(generated_pdf, official_pdf, dataset: nil, dispositions: nil)
    gen_text = pdf_text(generated_pdf)
    off_text = pdf_text(official_pdf)
    gen_rows = rows(gen_text)
    off_rows = rows(off_text)
    rows_eq, row_deltas = compare_rows(gen_rows, off_rows, dataset && dataset_index(dataset), gen_text, off_text)
    gen_words = prose_words(gen_text)
    off_words = prose_words(off_text)
    words_eq, prose_deltas = compare_prose(gen_words, off_words)
    deltas = row_deltas + prose_deltas
    problems = dispositions ? apply_dispositions(deltas, load_dispositions(dispositions)) : []
    {
      texts: { generated: gen_text, official: off_text },
      counts: {
        rows_generated: gen_rows.size, rows_official: off_rows.size, rows_matched: rows_eq,
        prose_words_generated: gen_words.size, prose_words_official: off_words.size,
        prose_words_matched: words_eq
      },
      deltas: deltas, problems: problems
    }
  end

  # What stops the run from passing: a bug or unreviewed delta, or a bad entry
  # in the dispositions file.
  def failures(result)
    open = result[:deltas].select { |d| %i[bug unreviewed].include?(d.disposition) }
    open.map { |d| "#{d.disposition}: #{d.text}" } + result.fetch(:problems, [])
  end

  def report(result)
    lines = result[:counts].map { |k, v| "#{k}: #{v}" }
    by = result[:deltas].group_by(&:disposition).transform_values(&:size)
    manual = result[:deltas].count(&:manual)
    lines << "deltas: #{result[:deltas].size} #{by.sort.to_h} (#{manual} settled by the dispositions file)"
    result[:deltas].each do |d|
      lines << "[#{d.layer}/#{d.side}] #{d.disposition}#{" (#{d.reason})" if d.reason}: #{d.text}"
    end
    lines.concat(result.fetch(:problems, []).map { |p| "problem: #{p}" })
    lines << (failures(result).empty? ? 'RESULT: PASS' : "RESULT: FAIL (#{failures(result).size} open)")
    lines.join("\n")
  end

  def main(argv)
    out = nil
    data = nil
    disp = nil
    opts = OptionParser.new do |o|
      o.on('--out DIR') { |v| out = v }
      o.on('--data FILE', 'dataset data.yaml: settles missing rows as data or bug') { |v| data = v }
      o.on('--dispositions FILE', 'checked-in human dispositions (YAML)') { |v| disp = v }
    end
    gen, off, *extra = opts.parse(argv)
    unless gen && off && extra.empty?
      warn 'usage: compare_official_pdf.rb GENERATED.pdf OFFICIAL.pdf [--out DIR] [--data data.yaml] ' \
           '[--dispositions FILE]'
      return 2
    end

    result = begin
      run(gen, off, dataset: data, dispositions: disp)
    rescue Errno::ENOENT, Psych::Exception => e
      raise UsageError, e.message.lines.first.to_s.strip
    end
    if out
      Dir.mkdir(out) unless Dir.exist?(out)
      File.write(File.join(out, 'generated.txt'), result[:texts][:generated])
      File.write(File.join(out, 'official.txt'), result[:texts][:official])
      File.write(File.join(out, 'report.txt'), report(result))
    end
    puts report(result)
    failures(result).empty? ? 0 : 1
  rescue OptionParser::ParseError, UsageError => e
    warn "compare_official_pdf: #{e.message}"
    2
  end
end

exit(OfficialPdfComparison.main(ARGV)) if $PROGRAM_NAME == __FILE__
