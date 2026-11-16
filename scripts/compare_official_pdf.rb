#!/usr/bin/env ruby
# frozen_string_literal: true

# Compares a generated Service Publication PDF against the official ITU PDF.
#
#   ruby scripts/compare_official_pdf.rb GENERATED.pdf OFFICIAL.pdf [--out DIR] [--data data.yaml]
#
# Both PDFs go through `pdftotext -layout`. Two layers are compared:
#   rows  - telegraph-office table rows (office name + office code), in order
#   prose - the preface words between "Note from TSB" and the first table header
# Every delta is printed with a heuristic disposition (data, layout, bug);
# the heuristic only settles what a measurement can settle. Anything it cannot
# settle is "unreviewed" and needs a human disposition (see docs/pdf).
require 'open3'
require 'optparse'
require 'set'
require 'yaml'

module OfficialPdfComparison
  CODE = /\A(?=.*[A-Z])[A-Z0-9-]{4}\z/
  FURNITURE = /\A\s*Annex to ITU OB|\A\s*Service Publication Annex|\A\s*ITUPublications/
  TABLE_HEADER = %r{Country\s*/\s*(?:[Gg]eographical|Network)}
  LIST_MARKER = /\A\s*(?:\d+\.|[a-z]\))\s+/

  Row = Struct.new(:name, :code, :line) do
    def key = code
    def to_s = "#{code} #{name}"
  end
  Delta = Struct.new(:layer, :side, :text, :disposition, :reason)

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

  # Rows: a layout line ending in a 4-char office code. The row key is the
  # code. The name is whatever precedes the code in its cell, or the previous
  # cell when the code stands alone. Names can wrap across lines, so the name
  # is only a lenient cross-check (see pair_delta).
  def rows(text)
    text.lines.each_with_index.filter_map do |raw, i|
      line = raw.delete("\f")
      cells = line.rstrip.split(/\s{2,}/).map(&:strip).reject(&:empty?)
      next if line =~ FURNITURE || cells.empty?

      m = cells.last.match(/(?:\A|\s)((?=[A-Z0-9-]*[A-Z])[A-Z0-9-]{4})(?:\d\)|[a-z]\)?|\*)?\z/)
      next unless m
      next if cells.size == 1 && (m.pre_match.empty? || line[/\A */].size < 20)

      name = m.pre_match.empty? ? cells[-2] : m.pre_match
      Row.new(squish(name), m[1], i + 1)
    end
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

  # Longest common subsequence diff; returns [[:eq|:del|:ins, a, b], ...]
  def diff(a, b, &key)
    key ||= :itself.to_proc
    ka = a.map(&key)
    kb = b.map(&key)
    n = ka.size
    m = kb.size
    t = Array.new(n + 1) { Array.new(m + 1, 0) }
    (n - 1).downto(0) do |i|
      (m - 1).downto(0) do |j|
        t[i][j] = ka[i] == kb[j] ? t[i + 1][j + 1] + 1 : [t[i + 1][j], t[i][j + 1]].max
      end
    end
    ops = []
    i = j = 0
    while i < n && j < m
      if ka[i] == kb[j]
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

  # generated is side A, official is side B.
  def compare_rows(generated_rows, official_rows, dataset_index = nil, generated_text = '')
    ops = diff(generated_rows, official_rows, &:key)
    deltas = hunks(ops).flat_map { |h| classify_row_hunk(h) }
    deltas.concat(name_deltas(ops, dataset_index))
    deltas.each { |d| disposition_from_dataset(d, dataset_index) } if dataset_index
    deltas.concat(unrendered_deltas(generated_rows, dataset_index, generated_text)) if dataset_index
    [ops.count { |o, *| o == :eq }, deltas]
  end

  # Rows that matched on code: compare the names leniently (wrapped names make
  # one side a prefix of the other).
  def name_deltas(ops, dataset_index)
    ops.filter_map do |op, gen, off|
      next unless op == :eq && normalise(gen.name) != normalise(off.name)

      pair = pair_delta(gen, off)
      settle_by_fragments(pair, gen, off, dataset_index) if pair.disposition == :unreviewed && dataset_index
      pair
    end
  end

  # pdftotext cuts a wrapped name at different lines in the two PDFs; when both
  # halves are fragments of one dataset name, the text is the same.
  def settle_by_fragments(delta, gen, off, dataset_index)
    g = normalise(gen.name)
    o = normalise(off.name)
    whole = dataset_index.fetch(gen.code, []).flatten.find { |n| n.include?(g) && n.include?(o) }
    return unless whole

    delta.disposition = :layout
    delta.reason = 'both names are fragments of one wrapped dataset name'
  end

  def classify_row_hunk(hunk)
    gen = hunk[:generated]
    off = hunk[:official]
    deltas = []
    gen.each { |r| deltas << Delta.new(:rows, :generated_only, r.to_s, :unreviewed, nil) }
    off.each { |r| deltas << Delta.new(:rows, :official_only, r.to_s, :unreviewed, nil) }
    gen_by_code = gen.group_by(&:code)
    off.each do |o|
      match = gen_by_code[o.code]&.first
      next unless match

      deltas.reject! { |d| [match.to_s, o.to_s].include?(d.text) && d.layer == :rows }
      deltas << pair_delta(match, o)
    end
    deltas
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
    when :generated_only
      unless in_data
        delta.disposition = :layout
        delta.reason = 'not an office code: wrapped text ending in a 4-letter word'
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

  def pair_delta(gen, off)
    text = "#{gen.code}: generated #{gen.name.inspect} vs official #{off.name.inspect}"
    g = normalise(gen.name)
    o = normalise(off.name)
    if g == o
      Delta.new(:rows, :both, text, :layout, 'case/punctuation/whitespace only')
    elsif o.start_with?(g) || g.start_with?(o)
      Delta.new(:rows, :both, text, :layout, 'name wrapped across lines; one side holds a prefix')
    else
      Delta.new(:rows, :both, text, :unreviewed, 'same code, different name')
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

  def run(generated_pdf, official_pdf, dataset: nil)
    gen_text = pdf_text(generated_pdf)
    off_text = pdf_text(official_pdf)
    gen_rows = rows(gen_text)
    off_rows = rows(off_text)
    rows_eq, row_deltas = compare_rows(gen_rows, off_rows, dataset && dataset_index(dataset), gen_text)
    gen_words = prose_words(gen_text)
    off_words = prose_words(off_text)
    words_eq, prose_deltas = compare_prose(gen_words, off_words)
    {
      texts: { generated: gen_text, official: off_text },
      counts: {
        rows_generated: gen_rows.size, rows_official: off_rows.size, rows_matched: rows_eq,
        prose_words_generated: gen_words.size, prose_words_official: off_words.size,
        prose_words_matched: words_eq
      },
      deltas: row_deltas + prose_deltas
    }
  end

  def report(result)
    lines = result[:counts].map { |k, v| "#{k}: #{v}" }
    by = result[:deltas].group_by(&:disposition).transform_values(&:size)
    lines << "deltas: #{result[:deltas].size} #{by.sort.to_h}"
    result[:deltas].each do |d|
      lines << "[#{d.layer}/#{d.side}] #{d.disposition}#{" (#{d.reason})" if d.reason}: #{d.text}"
    end
    lines.join("\n")
  end

  def main(argv)
    out = nil
    data = nil
    opts = OptionParser.new do |o|
      o.on('--out DIR') { |v| out = v }
      o.on('--data FILE', 'dataset data.yaml: settles missing rows as data or bug') { |v| data = v }
    end
    gen, off = opts.parse(argv)
    abort 'usage: compare_official_pdf.rb GENERATED.pdf OFFICIAL.pdf [--out DIR] [--data data.yaml]' unless gen && off

    result = run(gen, off, dataset: data)
    if out
      Dir.mkdir(out) unless Dir.exist?(out)
      File.write(File.join(out, 'generated.txt'), result[:texts][:generated])
      File.write(File.join(out, 'official.txt'), result[:texts][:official])
      File.write(File.join(out, 'report.txt'), report(result))
    end
    puts report(result)
  end
end

OfficialPdfComparison.main(ARGV) if $PROGRAM_NAME == __FILE__
