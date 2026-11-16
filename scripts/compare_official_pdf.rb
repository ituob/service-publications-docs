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
# non-zero while any bug, unreviewed delta or stale disposition remains.
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
  MAX_FRAGMENTS = 3
  MAX_SCAN = 6
  DISPOSITIONS = %w[data layout bug].freeze

  # A table row. A name that wraps leaves fragments on the lines around the
  # code line: pre (nearest first) and post. Which side of the code line the
  # wrap falls on differs between the two PDFs, so a row's name has several
  # candidate readings (variants); two rows have the same name only when one
  # reading of each is exactly equal.
  Row = Struct.new(:name, :code, :line, :col, :pre, :post) do
    def to_s = "#{code} #{name}"

    def variants
      @variants ||= (0..(pre || []).size).flat_map do |a|
        (0..(post || []).size).map do |b|
          normalise_words(((pre || []).first(a).reverse + [name] + (post || []).first(b)).join(' '))
        end
      end.to_set
    end

    def same_name?(other) = variants.intersect?(other.variants)

    private

    def normalise_words(str) = OfficialPdfComparison.normalise(str)
  end
  Delta = Struct.new(:layer, :side, :text, :disposition, :reason, :manual)

  module_function

  def pdf_text(path)
    out, err, st = Open3.capture3('pdftotext', '-layout', path, '-')
    raise "pdftotext failed for #{path}: #{err}" unless st.success?

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
    found.map do |i, (name, code, col)|
      Row.new(name, code, i + 1, col, fragments(lines, found, i, col, -1), fragments(lines, found, i, col, 1))
    end
  end

  # Text in the row's name column on the lines above (dir -1) or below (dir 1),
  # nearest first, up to the next row or page furniture. Blank lines, bare
  # footnote marks and other columns' text are skipped (at most MAX_SCAN lines).
  def fragments(lines, found, from, col, dir)
    out = []
    j = from + dir
    while out.size < MAX_FRAGMENTS && (j - from).abs <= MAX_SCAN && j >= 0 && j < lines.size
      break if found.key?(j) || lines[j] =~ FURNITURE

      cells = cells_at(lines[j])
      if cells.empty?
        j += dir # a blank line inside a cell (the generated PDF leaves one)
        next
      end

      cells = cells.reject { |t, _| t =~ FOOTNOTE }
      unless cells.empty?
        here = cells.select { |_, c| (c - col).abs <= COLUMN_SLACK }
        out << squish(here.map(&:first).join(' ')) unless here.empty?
      end
      j += dir
    end
    out
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

  # Rows that aligned but whose code-line names differ only because of wrapping.
  def name_deltas(ops)
    ops.filter_map do |op, gen, off|
      pair_delta(gen, off) if op == :eq && normalise(gen.name) != normalise(off.name)
    end
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

  # Same code on both sides. The names are the same text only when one reading
  # of each is exactly equal (see Row#variants): a name that gained or lost a
  # word is a bug, not a wrap.
  def pair_delta(gen, off)
    text = "#{gen.code}: generated #{gen.name.inspect} vs official #{off.name.inspect}"
    if normalise(gen.name) == normalise(off.name)
      Delta.new(:rows, :both, text, :layout, 'case/punctuation/whitespace only')
    elsif gen.same_name?(off)
      Delta.new(:rows, :both, text, :layout, 'name wrapped across lines; the joined lines are equal')
    else
      Delta.new(:rows, :both, text, :bug, 'same code, different name')
    end
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
    problems = dispositions ? apply_dispositions(deltas, YAML.safe_load_file(dispositions)) : []
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
    gen, off = opts.parse(argv)
    unless gen && off
      warn 'usage: compare_official_pdf.rb GENERATED.pdf OFFICIAL.pdf [--out DIR] [--data data.yaml] ' \
           '[--dispositions FILE]'
      return 2
    end

    result = run(gen, off, dataset: data, dispositions: disp)
    if out
      Dir.mkdir(out) unless Dir.exist?(out)
      File.write(File.join(out, 'generated.txt'), result[:texts][:generated])
      File.write(File.join(out, 'official.txt'), result[:texts][:official])
      File.write(File.join(out, 'report.txt'), report(result))
    end
    puts report(result)
    failures(result).empty? ? 0 : 1
  end
end

exit(OfficialPdfComparison.main(ARGV)) if $PROGRAM_NAME == __FILE__
