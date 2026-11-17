#!/usr/bin/env ruby
# frozen_string_literal: true

# Content fidelity of generated Service Publication PDFs against the official
# ITU PDFs of the same publication, edition and language.
#
#   ruby scripts/pdf_fidelity_report.rb GENERATED_DIR OFFICIAL_DIR [--out FILE]
#
# GENERATED_DIR holds <std>-<year>/<std>-<year>-<L>.pdf (the render layout);
# OFFICIAL_DIR holds T-SP-<std>-<year>-<L>.pdf (itu.int/dms_pub/itu-t/opb/sp/
# T-SP-<std>-<year>-PDF-<L>.pdf, saved under that name). Both go through
# `pdftotext -layout`; page furniture (running heads, page numbers, cover
# block) is dropped from both sides. Three layer measures, all against the
# official text (so a publication the official PDF has more of scores lower):
#
#   words  - recall: share of official words found in the generated PDF
#            (multiset); precision: share of generated words in the official.
#   order  - words in the same order: longest common subsequence / official.
#   rows   - table rows (a layout line of two or more cells): share of the
#            official rows whose cell text is also a generated row.
#   cells  - the same lines cell by cell: share of official cell values found
#            as a generated cell, wherever the columns put them.
#
# The measure settles what is in the PDF, not whether it is right: a gap is a
# data gap, a template gap or a layout difference only after reading the diff.
require 'open3'
require 'optparse'
require 'tempfile'

module PdfFidelity
  FURNITURE = [
    /\A\s*Annex to ITU OB/i, /\A\s*Service Publication Annex/i, /\A\s*ITU\s*Publications/i,
    /\A\s*Annexe? (?:au|à la|al|к)\b.*(?:BE|OB|UIT)/i, /\A\s*[–-]\s*\d+\s*[–-]\s*\z/
  ].freeze
  # A Han character is a word of its own: Chinese has no spaces to split on.
  WORD = /\p{Han}|[\p{L}\p{M}\p{N}&&[^\p{Han}]]+/
  Result = Struct.new(:words_official, :words_generated, :recall, :precision, :order, :rows_official, :rows_matched,
                      :cells_official, :cells_matched, :pages_official, :pages_generated) do
    def rows = rows_official.zero? ? nil : rows_matched.fdiv(rows_official)
    def cells = cells_official.zero? ? nil : cells_matched.fdiv(cells_official)
  end

  module_function

  def text(path)
    out, err, st = Open3.capture3('pdftotext', '-layout', path, '-')
    raise "pdftotext failed on #{path}: #{err}" unless st.success?

    out
  end

  def pages(path)
    out, = Open3.capture2('pdfinfo', path)
    out[/^Pages:\s+(\d+)/, 1].to_i
  end

  def lines(raw)
    # NBSP is layout padding too (`\s` misses it); invalid bytes must not raise.
    raw.scrub.tr("\u00A0", ' ').each_line.map(&:chomp).reject { |l| FURNITURE.any? { |f| l.match?(f) } }
  end

  def tokens(lines)
    lines.flat_map { |l| normalise(l).scan(WORD) }
  end

  def normalise(str) = str.unicode_normalize(:nfkc).downcase.tr("’‘", "''")

  # Multi-cell layout lines as the sequence of their normalised words.
  def rows(lines)
    lines.filter_map do |l|
      cells = l.strip.split(/\s{2,}/)
      next if cells.size < 2

      tokens(cells).join(' ')
    end
  end

  # The cells of those lines, each as its normalised words: a value is matched
  # wherever the columns put it, so a different column count does not hide it.
  def cells(lines)
    lines.flat_map do |l|
      parts = l.strip.split(/\s{2,}/)
      parts.size < 2 ? [] : parts.map { |c| tokens([c]).join(' ') }.reject(&:empty?)
    end
  end

  def multiset(items) = items.tally

  def overlap(a, b)
    ta = multiset(a)
    multiset(b).sum { |k, n| [n, ta.fetch(k, 0)].min }
  end

  # Longest common subsequence length via diff (a word is a line; the lines
  # only in the first file are the ones outside the subsequence), so a
  # 100k-word PDF is cheap.
  def lcs(a, b)
    Tempfile.create('fa') do |fa|
      Tempfile.create('fb') do |fb|
        fa.puts(a)
        fb.puts(b)
        [fa, fb].each(&:flush)
        out, = Open3.capture2('diff', '-d', fa.path, fb.path)
        a.size - out.lines.count { |l| l.start_with?('< ') }
      end
    end
  end

  def compare(generated, official)
    lg = lines(text(generated))
    lo = lines(text(official))
    tg = tokens(lg)
    to = tokens(lo)
    rg = rows(lg)
    ro = rows(lo)
    common = overlap(to, tg)
    co = cells(lo)
    Result.new(to.size, tg.size, to.empty? ? 0.0 : common.fdiv(to.size), tg.empty? ? 0.0 : common.fdiv(tg.size),
               to.empty? ? 0.0 : lcs(to, tg).fdiv(to.size), ro.size, overlap(ro, rg), co.size, overlap(co, cells(lg)),
               pages(official), pages(generated))
  end

  def pct(value) = value.nil? ? 'n/a' : format('%.1f', value * 100)

  def table(results)
    head = "| Publication | Lang | Words official | Recall % | Precision % | Order % | Rows official | Rows % | Cells % | Pages off/gen |\n" \
           "|---|---|---|---|---|---|---|---|---|---|\n"
    body = results.map do |(name, lang), r|
      "| #{name} | #{lang} | #{r.words_official} | #{pct(r.recall)} | #{pct(r.precision)} | #{pct(r.order)} | " \
        "#{r.rows_official} | #{pct(r.rows)} | #{pct(r.cells)} | #{r.pages_official}/#{r.pages_generated} |"
    end
    head + body.join("\n") + "\n"
  end

  def pairs(generated_dir, official_dir)
    Dir[File.join(generated_dir, '*', '*-[A-Z].pdf')].sort.filter_map do |gen|
      stem = File.basename(gen, '.pdf')
      lang = stem[-1]
      off = File.join(official_dir, "T-SP-#{stem[0..-3]}-#{lang}.pdf")
      [[stem[0..-3], lang], gen, off] if File.exist?(off)
    end
  end

  def run(argv)
    out = nil
    parser = OptionParser.new { |o| o.on('--out FILE') { |v| out = v } }
    gen_dir, off_dir = parser.parse(argv)
    abort 'usage: pdf_fidelity_report.rb GENERATED_DIR OFFICIAL_DIR [--out FILE]' unless gen_dir && off_dir

    results = pairs(gen_dir, off_dir).map { |key, g, o| [key, compare(g, o)] }
    md = table(results)
    out ? File.write(out, md) : puts(md)
    results
  end
end

PdfFidelity.run(ARGV) if $PROGRAM_NAME == __FILE__
