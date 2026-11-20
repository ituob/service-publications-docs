#!/usr/bin/env ruby
# frozen_string_literal: true

# Dispositions for the E.118, E.164B/C/D and E.180 rows of
# scripts/compare_official_pdf.rb (ituob/service-publications-docs#89).
#
#   ruby scripts/g1_row_dispositions.rb GEN_DIR OUT_DIR [PUB-LANG ...]
#
# GEN_DIR holds <short id>/<short id>-<L>.pdf (E.118-2018/E.118-2018-A.pdf). For
# every publication row the comparator runs, each open row delta goes through
# the rules below; the ones a rule settles are written to OUT_DIR/<PUB>-<L>.yaml
# in the --dispositions format. A delta no rule settles stays open
# ("unreviewed") and is counted, never written. Prose deltas are not settled
# here (see README-g1.adoc).
#
# A rule fires on a measurement, not on a guess. Words are compared as a bag
# per row (gi = words only the generated row has, oi = only the official one):
#   layout  gi and oi are empty AND every column (the " | " cells of the row text)
#           holds the same words on both sides: the same words, in another line
#           of the same cell. Words that moved to another column are not layout;
#   data    every word of gi is a word of the dataset record(s) for that row in
#           the PDF's language, so the generated PDF prints what the dataset
#           holds and the official list differs from the dataset (the official
#           words are not all in the record: else the generator dropped text);
#   bug     gi is the dataset's text in ANOTHER language than the PDF's, or, in
#           the E.118 A/C/R PDFs, the English contact labels Tel/Fax/E-mail that
#           the official PDF translates.
require 'yaml'
require_relative 'compare_official_pdf'

module G1RowDispositions
  LANGS = { 'E' => 'en', 'F' => 'fr', 'S' => 'es', 'A' => 'ar', 'C' => 'zh', 'R' => 'ru' }.freeze
  LABELS = %w[tel fax e mail].freeze
  FAMILIES = {
    'T-SP-E.118-2018' => { shape: 'IssuerIdentifierList', dataset: 'datasets/1161-E.118/data.yaml', code: 'issue_id_number' },
    'T-SP-E.164B-2012' => { shape: 'CountryCodeTable', dataset: 'datasets/1015-E.164B/data.yaml', code: 'country_code' },
    'T-SP-E.164C-2011' => { shape: 'CountryCodeTable', dataset: 'datasets/994-E.164C/data.yaml', code: 'country_code', skip: %w[note], markers: (1..30).map(&:to_s) },
    'T-SP-E.164D-2016' => { shape: 'CountryCodeTable', dataset: 'datasets/1114-E.164D/data.yaml', code: 'country_code', markers: ('a'..'z').to_a },
    'T-SP-E.180-2010' => { shape: 'ToneList', dataset: 'datasets/955-E.180/data.yaml', code: nil }
  }.freeze
  ROOT = File.expand_path('..', __dir__)
  PAIR = /\A(.*?): generated "(.*)" vs official "(.*)"\z/m

  Verdict = Struct.new(:disposition, :reason)

  module_function

  # Arabic words have their letters sorted, as the shape's mirror_letters does
  def words(str)
    str.to_s.unicode_normalize(:nfkc).downcase.gsub(/[\u0600-\u06FF]+/) { |w| w.chars.sort.join }.scan(/[[:alnum:]]+/)
  end

  COLUMN_SEP = ' | '

  # the " | " cells of a row text hold the same words, column by column
  def same_columns?(gen_text, off_text)
    g = gen_text.to_s.split(COLUMN_SEP, -1)
    o = off_text.to_s.split(COLUMN_SEP, -1)
    g.size == o.size && g.zip(o).all? { |a, b| words(a).sort == words(b).sort }
  end

  # words of left that right lacks, counting repeats
  def minus(left, right)
    rest = left.dup
    right.each { |w| (i = rest.index(w)) && rest.delete_at(i) }
    rest
  end

  # the text values of a record field: one language, or (any) every language
  def leaves(value, lang, any)
    case value
    when Hash then any ? value.values.flat_map { |v| leaves(v, lang, any) } : leaves(value[lang] || value['en'], lang, any)
    when Array then value.flat_map { |v| leaves(v, lang, any) }
    else [value.to_s]
    end
  end

  # Dataset records by row key. E.118 and E.164 keys hold the code ("89 93 01",
  # read in either direction for the right-to-left PDFs, or "86|China"); E.180
  # rows have no code and are found by the first word of the country name.
  class Dataset
    def initialize(family)
      data = YAML.safe_load_file(File.join(ROOT, family[:dataset]))
      @records = data.is_a?(Hash) ? data.values.first : data
      @code = family[:code]
      @skip = family[:skip] || [] # fields printed outside the row (E.164C footnotes)
      @markers = family[:markers] || [] # footnote marks a row prints for its note
    end

    def records(key)
      return by_country(key) unless @code

      code, name = key.split('|', 2)
      found = @records.select { |r| same_code?(r[@code].to_s, code) }
      found.size > 1 && name ? narrow(found, name) : found
    end

    def words(key, lang, any: false, markers: true)
      records(key).flat_map { |r| record_words(r, lang, any, markers) }
    end

    private

    # A record with a note prints a footnote mark in its row (a number in E.164C,
    # a letter in E.164D); the mark is the row's own, not a word of the record,
    # so it counts as a word of the record only where `markers` is true.
    def record_words(record, lang, any, markers)
      text = record.reject { |k, _| @skip.include?(k) }.values.flat_map { |v| G1RowDispositions.leaves(v, lang, any) }
      marks = markers && record.key?('note') ? @markers : []
      text.flat_map { |s| G1RowDispositions.words(s) } + marks
    end

    def same_code?(record, key) = record.delete(' ') == key.delete(' ') || record.split.reverse == key.split

    def first_word(str) = G1RowDispositions.words(str).first

    def named?(record, word) = record.values.grep(Hash).any? { |h| h.values.any? { |n| first_word(n) == word } }

    def narrow(found, name)
      hit = found.select { |r| named?(r, first_word(name)) }
      hit.empty? ? found : hit
    end

    def by_country(key) = @records.select { |r| (r['country_or_area'] || {}).values.any? { |n| first_word(n) == first_word(key) } }
  end

  def verdict(pub, lang, key, gen_text, off_text, dataset)
    g = words(gen_text)
    o = words(off_text)
    gi = minus(g, o)
    oi = minus(o, g)
    if gi.empty? && oi.empty?
      return Verdict.new(:layout, 'same words in every column on both sides: the two PDFs wrap a cell or place a continuation line differently') if same_columns?(gen_text, off_text)

      return nil # the row bag is equal but a word sits in another column: not a layout difference
    end

    code = LANGS.fetch(lang)
    mine = dataset.words(key, code)
    return nil if mine.empty?

    # what the dataset holds beyond what the generated row printed
    unprinted = minus(dataset.words(key, code, markers: false), g)

    if gi.empty?
      # the generated row lost words: the dataset holds them (the generator
      # dropped dataset text) or it does not (the official list has more)
      return minus(oi, unprinted).empty? ? Verdict.new(:bug, "the dataset record holds #{oi.join(' ')} (in #{code}) once more than the generated row prints it, and the official row prints it") : Verdict.new(:data, "the official PDF prints #{oi.join(' ')} once more than the dataset record holds (in #{code}); the generated PDF prints the dataset")
    end

    if %w[A C R].include?(lang) && pub == 'T-SP-E.118-2018' && (gi & LABELS).any? && minus(gi - LABELS, mine).empty?
      Verdict.new(:bug, 'the generated PDF prints the contact labels Tel/Fax/E-mail in English (and the country name, the dataset has en only) where the official PDF translates them')
    elsif minus(gi, mine).empty? && (oi.empty? || minus(oi, unprinted).any?)
      Verdict.new(:data, "the generated PDF prints what the dataset holds for this row in #{code} (#{gi.join(' ')}); the official PDF has #{oi.empty? ? 'other text' : oi.join(' ')}")
    elsif minus(gi, mine).any? && minus(gi, dataset.words(key, code, any: true)).empty?
      Verdict.new(:bug, "the generated PDF prints the dataset's text of another language than #{code} (#{gi.join(' ')})")
    end
  end

  def rows(text, pub) = OfficialPdfComparison.shape(FAMILIES.fetch(pub)[:shape]).rows(text)

  # Settled row deltas as dispositions entries, and how many row deltas stay open.
  def entries(result, pub, lang, dataset)
    gen_rows = rows(result[:texts][:generated], pub)
    off_rows = rows(result[:texts][:official], pub)
    ctx = { pub: pub, lang: lang, dataset: dataset,
            gen_by: gen_rows.to_h { |r| [r.to_s, r] }, off_by: off_rows.to_h { |r| [r.to_s, r] },
            gen_key: gen_rows.to_h { |r| [r.key, r] }, off_key: off_rows.to_h { |r| [r.key, r] } }
    out = []
    open = 0
    result[:deltas].each do |d|
      next unless %i[bug unreviewed].include?(d.disposition) && d.layer == :rows

      v = row_verdict(d, ctx)
      # E.180 only gets the layout rule: its footnote letters ("a)") and multi-line
      # tone cells were not checked against the data/bug rules, so those stay open
      v = nil if pub == 'T-SP-E.180-2010' && v&.disposition != :layout
      v ? out << { 'layer' => d.layer.to_s, 'side' => d.side.to_s, 'text' => d.text, 'disposition' => v.disposition.to_s, 'reason' => v.reason } : open += 1
    end
    [out, open]
  end

  PROSE_PAIR = /\Agenerated "(.*)" vs official "(.*)"\z/m
  PROSE_LAYOUT = 'the prose words of the row are the same on both sides once the page numbers of the footers ' \
                 '(numbers of up to two digits), the "N.º" of the Spanish footer and the hyphenation ' \
                 '"ITU-T" / "ITUT" are set aside: the PDFs break pages and lines differently'

  # Prose deltas are settled only for a row whose whole prose difference is
  # page furniture: the unreviewed prose deltas, taken together as a word bag,
  # differ only in page numbers, "N.º" and the ITU-T hyphenation. Any other
  # word difference leaves all of the row's prose deltas unreviewed.
  def prose_entries(result)
    deltas = result[:deltas].select { |d| d.layer == :prose && d.disposition == :unreviewed }
    return [] if deltas.empty?

    gen = []
    off = []
    deltas.each do |d|
      m = d.text.match(PROSE_PAIR) or return []
      next unless d.side == :both

      gen += furniture_free(m[1])
      off += furniture_free(m[2])
    end
    return [] unless minus(gen, off).empty? && minus(off, gen).empty?

    deltas.map { |d| { 'layer' => 'prose', 'side' => d.side.to_s, 'text' => d.text, 'disposition' => 'layout', 'reason' => PROSE_LAYOUT } }
  end

  def furniture_free(str)
    words(str.gsub(/\bITU[- ]?T\b/i, 'itut')).reject { |w| w.match?(/\A\d{1,2}\z/) || %w[n o].include?(w) }
  end

  def row_verdict(delta, ctx)
    args = [ctx[:pub], ctx[:lang]]
    case delta.side
    when :both
      m = delta.text.match(PAIR) or return nil
      verdict(*args, m[1], m[2], m[3], ctx[:dataset])
    when :generated_only
      row = ctx[:gen_by][delta.text] or return nil
      off = ctx[:off_key][row.key] or return unpaired(*args, row, ctx[:dataset], :generated)
      moved(verdict(*args, row.key, row.text, off.text, ctx[:dataset]), row.key)
    when :official_only
      row = ctx[:off_by][delta.text] or return nil
      gen = ctx[:gen_key][row.key] or return unpaired(*args, row, ctx[:dataset], :official)
      moved(verdict(*args, row.key, gen.text, row.text, ctx[:dataset]), row.key)
    end
  end

  # A row only one PDF has under that key. The generated row is settled when it
  # is, word for word, what the dataset holds for its code (the official list
  # has no such row); the official row when some of its words are not in the
  # dataset records of its code (the generator has nothing to print there).
  def unpaired(_pub, lang, row, dataset, side)
    code = LANGS.fetch(lang)
    base = row.key.sub(/#\d+\z/, '')
    mine = dataset.words(base, code)
    return nil if mine.empty?

    own = words(row.text)
    if side == :generated && minus(own, mine).empty?
      Verdict.new(:data, "the generated row is what the dataset holds for #{base.split('|').first} in #{code}; the official list has no row of that name under this code (the dataset differs from the official list)")
    elsif side == :official && minus(own, mine).any?
      Verdict.new(:data, "the official row has words (#{minus(own, mine).first(6).join(' ')}) that the dataset records of #{base.split('|').first} in #{code} do not hold, so the generated PDF cannot print it")
    end
  end

  # the row is on both sides, at another position: the rule that settles its
  # words settles it, with the position named
  def moved(verdict, key)
    return nil unless verdict

    name = key.split('|', 2)[1].to_s.sub(/#\d+\z/, '')
    # the official lists put the "Reserved ..." entries last, whatever the letters
    if verdict.disposition == :layout && accented?(name) && !name.match?(/\Ar[ée]serv/i)
      Verdict.new(:bug, "the alphabetical list puts #{name} at another place than the official list: the generated PDF sorts accented letters after the unaccented ones, the official list sorts them with their base letter")
    else
      Verdict.new(verdict.disposition, "the row sits at another position of its list than in the other PDF (the lists are sorted differently); #{verdict.reason}")
    end
  end

  def accented?(word) = word.match?(/\p{Latin}/) && word != word.unicode_normalize(:nfd).gsub(/\p{M}/, '')

  def main(gen_dir, out_dir, only)
    Dir.mkdir(out_dir) unless Dir.exist?(out_dir)
    FAMILIES.each do |pub, family|
      short = pub.delete_prefix('T-SP-')
      dataset = Dataset.new(family)
      Dir[File.join(ROOT, 'docs/pdf/official', "#{pub}-?.pdf")].sort.each do |off_pdf|
        lang = File.basename(off_pdf, '.pdf')[-1]
        next if only.any? && !only.include?("#{pub}-#{lang}")

        result = OfficialPdfComparison.run(File.join(gen_dir, short, "#{short}-#{lang}.pdf"), off_pdf, shape: family[:shape], lang: lang)
        list, open_rows = entries(result, pub, lang, dataset)
        list += prose_entries(result)
        File.write(File.join(out_dir, "#{pub}-#{lang}.yaml"), list.to_yaml.sub(/\A---\n/, ''))
        puts format('%-17s %s settled=%-5d bug=%-4d rows-open=%d', pub, lang, list.size, list.count { |e| e['disposition'] == 'bug' }, open_rows)
      end
    end
  end
end

G1RowDispositions.main(ARGV[0], ARGV[1], ARGV.drop(2)) if $PROGRAM_NAME == __FILE__
