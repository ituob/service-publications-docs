#!/usr/bin/env ruby
# frozen_string_literal: true

# Interim row-level comparison for the E.118, E.164B/C/D and E.180 shapes
# (ituob/service-publications-docs#89). Reads the generated and official PDFs
# through `pdftotext -layout`, lets the shape cut both into rows, aligns the rows
# by key and writes one dispositions file per publication row:
#
#   ruby scripts/g1_row_dispositions.rb GEN_DIR OUT_DIR [PUB-LANG ...]
#
# GEN_DIR holds <short id>/<short id>-<L>.pdf (E.118-2018/E.118-2018-A.pdf).
# The delta text and the rules below are this script's own: they settle what a
# measurement settles (same words in another order, a localised country name or
# label the dataset does not carry) and leave everything else "unreviewed".
require 'open3'
require 'yaml'
require_relative 'official_pdf_shapes/g1_support'
Dir[File.join(__dir__, 'official_pdf_shapes', '*.rb')].sort.each { |f| require f unless f.end_with?('g1_support.rb') }

module G1RowDispositions
  SHAPES = {
    'T-SP-E.118-2018' => OfficialPdfComparison::Shapes::IssuerIdentifierList,
    'T-SP-E.164B-2012' => OfficialPdfComparison::Shapes::CountryCodeTable,
    'T-SP-E.164C-2011' => OfficialPdfComparison::Shapes::CountryCodeTable,
    'T-SP-E.164D-2016' => OfficialPdfComparison::Shapes::CountryCodeTable,
    'T-SP-E.180-2010' => OfficialPdfComparison::Shapes::ToneList
  }.freeze
  LABELS = %w[tel fax e mail].freeze
  # words of the national-number cell the dataset holds in English only
  NUMBER_WORDS = %w[digits to up].freeze

  Delta = Struct.new(:text, :disposition, :reason)

  module_function

  def norm(str) = str.downcase.gsub(/[^[:alnum:]]+/, ' ').strip

  def pdf_text(path)
    out, err, st = Open3.capture3('pdftotext', '-layout', path, '-')
    abort "pdftotext failed for #{path}: #{err}" unless st.success?
    out
  end

  # words of a that b does not have, counting repeats
  def minus(left, right)
    rest = left.dup
    right.each { |w| (i = rest.index(w)) && rest.delete_at(i) }
    rest
  end

  def deltas(pub, lang, gen_rows, off_rows)
    gen = gen_rows.to_h { |r| [r.key, r] }
    off = off_rows.to_h { |r| [r.key, r] }
    out = []
    (gen.keys & off.keys).each do |key|
      g = norm(gen[key].text).split
      o = norm(off[key].text).split
      next if g == o

      out << classify(pub, lang, key, minus(g, o), minus(o, g))
    end
    (gen.keys - off.keys).each { |k| out << Delta.new("#{k}: generated row has no official row", :unreviewed, nil) }
    (off.keys - gen.keys).each { |k| out << Delta.new("#{k}: official row has no generated row", :unreviewed, nil) }
    out
  end

  def classify(pub, lang, key, gi, oi)
    text = "#{key}: generated-only #{gi.inspect} vs official-only #{oi.inspect}"
    return Delta.new(text, :layout, 'same words in another order: the two PDFs wrap a cell or place a continuation line differently') if gi.empty? && oi.empty?

    case pub
    when 'T-SP-E.118-2018' then issuer(text, lang, gi, oi)
    when 'T-SP-E.164C-2011' then dialling(text, gi, oi)
    else Delta.new(text, :unreviewed, nil)
    end
  end

  def issuer(text, lang, gi, oi)
    labels = gi & LABELS
    if %w[A C R].include?(lang) && labels.any?
      Delta.new(text, :bug, 'the generated PDF prints the English labels Tel/Fax/E-mail where the official one has them translated; the generator does not translate the contact labels for A, C and R' \
                            "#{', and the country name is English (dataset has en only)' if (gi - LABELS).any?}")
    elsif lang != 'E' && labels.empty? && gi.any?
      Delta.new(text, :data, 'the dataset (datasets/1161-E.118/data.yaml) holds country_or_area in English only; the official PDF prints the translated country name')
    else
      Delta.new(text, :unreviewed, nil)
    end
  end

  def dialling(text, gi, oi)
    if gi.sort == %w[0] && oi.sort == %w[utc]
      Delta.new(text, :data, "the dataset holds utc_dst '0'; the official PDF prints UTC for a zero offset")
    elsif (gi - NUMBER_WORDS - %w[0]).empty? && oi.size >= gi.count { |w| NUMBER_WORDS.include?(w) } && (oi & %w[chiffres cifras dígitos]).any?
      Delta.new(text, :data, 'the dataset holds national_sig_number as one English string ("9 digits"); the official PDF prints it translated')
    else
      Delta.new(text, :unreviewed, nil)
    end
  end

  def entries(deltas)
    deltas.reject { |d| d.disposition == :unreviewed }.map do |d|
      { 'layer' => 'rows', 'side' => 'both', 'text' => d.text, 'disposition' => d.disposition.to_s, 'reason' => d.reason }
    end
  end

  def main(gen_dir, out_dir, only)
    Dir.mkdir(out_dir) unless Dir.exist?(out_dir)
    root = File.expand_path('..', __dir__)
    rows = []
    SHAPES.each do |pub, shape|
      short = pub.delete_prefix('T-SP-')
      Dir[File.join(root, 'docs/pdf/official', "#{pub}-?.pdf")].sort.each do |off_pdf|
        lang = File.basename(off_pdf, '.pdf')[-1]
        next if only.any? && !only.include?("#{pub}-#{lang}")

        gen_pdf = File.join(gen_dir, short, "#{short}-#{lang}.pdf")
        ds = deltas(pub, lang, shape.new.rows(pdf_text(gen_pdf)), shape.new.rows(pdf_text(off_pdf)))
        File.write(File.join(out_dir, "#{pub}-#{lang}.yaml"), entries(ds).to_yaml)
        rows << [pub, lang, ds.size, ds.count { |d| d.disposition != :unreviewed }, ds.count { |d| d.disposition == :bug }, ds.count { |d| d.disposition == :unreviewed }]
      end
    end
    rows.each { |r| puts format('%-18s %s deltas=%-5d dispositioned=%-5d bug=%-5d unreviewed=%d', *r) }
  end
end

G1RowDispositions.main(ARGV[0], ARGV[1], ARGV.drop(2)) if $PROGRAM_NAME == __FILE__
