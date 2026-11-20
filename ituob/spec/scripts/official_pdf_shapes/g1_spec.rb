# frozen_string_literal: true

require 'spec_helper'

require File.expand_path('../../../../scripts/compare_official_pdf', __dir__)

%w[country_code_table issuer_identifier_list tone_list].each { |f| require File.expand_path("../../../../scripts/official_pdf_shapes/#{f}", __dir__) }

# Synthetic `pdftotext -layout` fixtures for the G1 shapes (E.118, E.164B/C/D,
# E.180). No PDF is read.
RSpec.describe 'G1 official PDF shapes' do

  def table_pages(rows_per_page, pages)
    Array.new(pages) do |p|
      body = Array.new(rows_per_page) { |i| format('%-30s %d', "Country#{p}x#{i}", p * 10 + i + 1) }
      (["Annex #{p}", 'Country              Code', ''] + body + ['', "footer #{p}"]).join("\n")
    end.join("\f")
  end

  describe OfficialPdfComparison::Shapes::CountryCodeTable do
    subject(:shape) { described_class.new }

    let(:text) { "Preface text\n2 a numbered paragraph\n3 another one\n\f" + table_pages(10, 3) }

    it 'reads one row per table line with the key code|first name word' do
      keys = shape.rows(text).map(&:key)
      expect(keys.size).to eq(30)
      expect(keys.first).to eq('1|Country0x0')
    end

    it 'does not read the numbered paragraphs of a preface page as rows' do
      expect(shape.rows(text).map(&:key)).not_to include('2|a', '3|another')
    end

    it 'joins a wrapped name under its row into the same row' do
      wrapped = text.sub("Country1x3                     14\n", "Country1x3                     14\n  (Republic of)\n")
      row = shape.rows(wrapped).find { |r| r.key == '14|Country1x3' }
      expect(row.text).to include('Republic')
    end

    it 'ends the prose where the table starts' do
      lines = text.lines.map(&:chomp)
      stop = shape.prose_stop(lines, 0)
      expect(lines[stop..].join("\n")).to include('Country0x0')
      expect(lines[0...stop].join("\n")).not_to include('Country0x0')
    end
  end

  describe OfficialPdfComparison::Shapes::IssuerIdentifierList do
    subject(:shape) { described_class.new }

    let(:text) do
      ["Preface line", "\f", 'Country   Company          IIN        Contact',
       'Canada    ACME CORP        89 1 001   Tel 1', '          Toronto', 'France    ZED SA           89 33 002  Tel 2',
       'Peru      Beta             89 51 003  Tel 3', '', '2. AMENDMENTS', 'Amend text'].join("\n")
    end

    it 'keys each row by its IIN and keeps wrapped lines in the row' do
      rows = shape.rows(text)
      expect(rows.map(&:key)).to eq(['89 1 001', '89 33 002', '89 51 003'])
      expect(rows.first.text).to include('Toronto')
    end

    it 'closes the last row at the numbered section heading' do
      expect(shape.rows(text).last.text).not_to include('Amend')
    end

    it 'ends the prose before the first row' do
      lines = text.lines.map(&:chomp)
      stop = shape.prose_stop(lines, 0)
      expect(lines[0...stop].join("\n")).not_to include('ACME')
    end
  end

  describe OfficialPdfComparison::Shapes::ToneList do
    subject(:shape) { described_class.new }

    let(:text) do
      ['Preface', '', 'Canada', 'Busy tone -            480+620        0.5 on 0.5 off',
       'Dial tone -            350+440        continuous', '', 'France', 'Busy tone -            440            0.5 on 0.5 off', '', 'page footer'].join("\n")
    end

    it 'makes one row per country with its tones' do
      rows = shape.rows(text)
      expect(rows.size).to eq(2)
      expect(rows.first.text).to include('Dial tone')
    end

    it 'ends the prose before the first country heading' do
      lines = text.lines.map(&:chomp)
      expect(lines[0...shape.prose_stop(lines, 0)].join("\n")).not_to include('480')
    end
  end

  describe 'classifier word bag' do
    it 'sorts the letters of Arabic words so both PDFs compare equal' do
      load File.expand_path('../../../../scripts/g1_row_dispositions.rb', __dir__) unless defined?(G1RowDispositions)
      expect(G1RowDispositions.words('كتاب')).to eq(G1RowDispositions.words('تكاب'))
    end

    describe 'layout rule per column' do
      before { load File.expand_path('../../../../scripts/g1_row_dispositions.rb', __dir__) unless defined?(G1RowDispositions) }

      def verdict(gen, off) = G1RowDispositions.verdict('T-SP-E.180-2010', 'E', 'Cuba', gen, off, nil)

      it 'is layout when every column holds the same words (a wrap inside a cell)' do
        v = verdict('Cuba | Busy tone Dial tone | 425 425', 'Cuba | Dial tone Busy tone | 425 425')
        expect(v&.disposition).to eq(:layout)
      end

      it 'is not layout when the row bag is equal but a word sits in another column' do
        expect(verdict('Cuba | Busy tone | 425 Dial', 'Cuba | Busy tone Dial | 425')).to be_nil
      end

      it 'is not layout when the column count differs' do
        expect(verdict('Cuba | Busy tone | 425', 'Cuba | Busy tone 425')).to be_nil
      end

      it 'is not layout when only a trailing empty column differs' do
        expect(verdict('Cuba | Busy tone | 425', 'Cuba | Busy tone | 425 | ')).to be_nil
      end

      it 'is not layout when columns hold equal word counts but different words' do
        expect(verdict('Cuba | Busy Dial | tone 425', 'Cuba | Busy tone | Dial 425')).to be_nil
      end
    end
  end
end
