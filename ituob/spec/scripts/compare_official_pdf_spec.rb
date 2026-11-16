# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'yaml'

require File.expand_path('../../../scripts/compare_official_pdf', __dir__)

# Exercises the diff logic of scripts/compare_official_pdf.rb on small layout
# text fixtures (what `pdftotext -layout` prints); no PDF is read.
RSpec.describe OfficialPdfComparison do
  subject(:mod) { described_class }

  let(:generated_text) do
    <<~TXT
      Note from TSB

      a)  The new List replaces the old one.

      Country /      Network     Network   Name of     Office
      AFGHANISTAN                  AF- -   Kabul        AFKL
                                           All others   AFKX
      Annex to ITU OB No. 32-E        - 1 -
                                          Freeport Grand     BSFP
                                          Bahama
                                          Nassau Bahamas BSNU
      ÉMIRATS ARABES UNIS
    TXT
  end

  let(:official_text) do
    <<~TXT
      Note from TSB

      1.  The new  List replaces the old one.

      Country /geographical area   Network   Network code   Name of   Office code
      AFGHANISTAN        Kabul                  AF- -   Kabul        AFKL
      AFGHANISTAN                                       All others   AFKX
      Annex to ITU OB 980-E      - 2 -          15.V.2011
      BAHAMAS                                   Freeport Grand Bahama   BSFP
      BAHAMAS                                   Nassau Bahamas          BSNU
      BELARUS                                   All destinations        BYXX
      Geneva, 2011
    TXT
  end

  describe '.rows' do
    it 'keys rows on the 4-character office code and keeps the name cell' do
      expect(mod.rows(generated_text).map(&:to_s)).to eq(
        ['AFKL Kabul', 'AFKX All others', 'BSFP Freeport Grand', 'BSNU Nassau Bahamas']
      )
    end

    it 'ignores page furniture, a bare year and a country name ending in four capitals' do
      codes = mod.rows(official_text).map(&:code)
      expect(codes).to eq(%w[AFKL AFKX BSFP BSNU BYXX])
      expect(mod.rows("Geneva,   2011\nÉMIRATS ARABES UNIS\n")).to be_empty
    end

    it 'reads the form-feed-prefixed first line of a page and hyphen codes with footnote marks' do
      text = "\f                                              Nassau Bahamas BSNU\n" \
             "                              Antofagasta        --AF\n" \
             "                              All destinations   AAXX2)\n"
      expect(mod.rows(text).map(&:code)).to eq(%w[BSNU --AF AAXX])
    end
  end

  describe '.prose_words' do
    it 'covers the text between "Note from TSB" and the first table header, minus list markers' do
      expect(mod.prose_words(generated_text)).to eq(%w[Note from TSB The new List replaces the old one.])
      expect(mod.prose_words(official_text)).to eq(%w[Note from TSB The new List replaces the old one.])
    end
  end

  describe '.diff and .hunks' do
    it 'groups consecutive differences into one hunk each' do
      ops = mod.diff(%w[a b c d e], %w[a x y d f])
      expect(mod.hunks(ops)).to eq(
        [{ generated: %w[b c], official: %w[x y] }, { generated: %w[e], official: %w[f] }]
      )
    end

    it 'reports no hunk for equal sequences' do
      expect(mod.hunks(mod.diff(%w[a b], %w[a b]))).to be_empty
    end
  end

  describe '.run' do
    before do
      @tmp = Dir.mktmpdir
      File.write(File.join(@tmp, 'data.yaml'), [
        ['AFKL', 'Kabul'], ['AFKX', 'All others'], ['BSFP', 'Freeport Grand Bahama'],
        ['BSNU', 'Nassau Bahamas'], ['ZZ99', 'Never rendered']
      ].map { |c, n| { 'office_code' => c, 'telegraph_office_name' => { 'en' => n } } }.to_yaml)
      allow(mod).to receive(:pdf_text).with('gen.pdf').and_return(generated_text)
      allow(mod).to receive(:pdf_text).with('off.pdf').and_return(official_text)
    end
    after { FileUtils.remove_entry(@tmp) }

    let(:result) { mod.run('gen.pdf', 'off.pdf', dataset: File.join(@tmp, 'data.yaml')) }

    it 'counts rows and matches' do
      expect(result[:counts]).to include(rows_generated: 4, rows_official: 5, rows_matched: 4)
    end

    it 'dispositions a wrapped name as layout, a row absent from the dataset as data, and an unrendered record as bug' do
      by_text = result[:deltas].to_h { |d| [d.text[/\A[^\s:]+/], d] }
      expect(by_text['BSFP']).to have_attributes(disposition: :layout, side: :both)
      expect(by_text['BYXX']).to have_attributes(disposition: :data, side: :official_only)
      expect(by_text['ZZ99']).to have_attributes(disposition: :bug, side: :dataset_only)
    end

    it 'sees no prose delta when only list markers and spacing differ' do
      expect(result[:deltas].select { |d| d.layer == :prose }).to be_empty
      expect(result[:counts]).to include(prose_words_generated: 10, prose_words_matched: 10)
    end

    it 'leaves a changed word and an unrelated name for a human (unreviewed)' do
      changed = official_text.sub('the old one', 'the older list').sub('Nassau Bahamas', 'Hamilton')
      allow(mod).to receive(:pdf_text).with('off.pdf').and_return(changed)
      deltas = result[:deltas]
      expect(deltas.select { |d| d.layer == :prose }).to all(have_attributes(disposition: :unreviewed))
      expect(deltas.select { |d| d.layer == :prose }).not_to be_empty
      expect(deltas.find { |d| d.text.start_with?('BSNU') }).to have_attributes(disposition: :unreviewed)
    end

    it 'prints a summary line with counts by disposition' do
      expect(mod.report(result)).to match(/deltas: 3 \{bug: 1, data: 1, layout: 1\}/)
    end
  end
end
