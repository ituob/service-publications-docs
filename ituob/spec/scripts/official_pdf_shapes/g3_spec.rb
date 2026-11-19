# frozen_string_literal: true

require 'spec_helper'

require File.expand_path('../../../../scripts/compare_official_pdf', __dir__)

# Synthetic `pdftotext -layout` fixtures for the #89 G3 shapes. No PDF is read.
RSpec.describe 'G3 official PDF shapes' do
  def shape(name) = OfficialPdfComparison.shape(name)
  def pairs(rows) = rows.map { |r| [r.key, r.text] }

  describe 'F68TelexCodes' do
    subject(:sh) { shape('F68TelexCodes') }

    let(:text) do
      <<~TXT
        Notes from TSB
        1. Some preface sentence.

        TDC   TNIC   Name
        592   SR     Suriname
        810   RU     Russia
              SU
        93ª   Foo    Bar
        Annex to ITU OB 980-E        - 3 -

        ABBREVIATIONS
        VTR   Voie de transmission
              rapide
        APPENDIX 1
        A   AB   Afghanistan
        APPENDIX 2
        OB     Country
        975  Chile         976  Peru
      TXT
    end

    it 'stops the preface at the TDC table header' do
      lines = text.lines.map(&:rstrip)
      start = sh.prose_start(lines, 'E')
      expect(start).to eq(0)
      expect(lines[sh.prose_stop(lines, start)]).to start_with('TDC')
    end

    it 'reads TDC rows with network code, merges the second code and accepts ordinal marks' do
      rows = pairs(sh.rows(text))
      expect(rows).to include(['TDC 592', 'SR Suriname'], ['TDC 810', 'RU / SU Russia'], ['TDC 93', 'Foo Bar'])
    end

    it 'reads abbreviations (wrapped), appendix 1 and appendix 2 pairs, dropping page furniture' do
      rows = pairs(sh.rows(text))
      expect(rows).to include(['ABBR VTR', 'Voie de transmission rapide'], ['TNIC A', 'AB Afghanistan'],
                              ['OB 975', 'Chile'], ['OB 976', 'Peru'])
      expect(rows.flatten.join(' ')).not_to include('Annex to ITU')
    end

    it 'returns tables in a fixed order: TDC, TNIC, OB, ABBR' do
      expect(sh.rows(text).map { |r| r.key.split.first }.uniq).to eq(%w[TDC TNIC OB ABBR])
    end
  end

  describe 'F1CodeGroups' do
    subject(:sh) { shape('F1CodeGroups') }

    let(:text) do
      <<~TXT
        Note from the TSB
        Preface text.

        Part I - Decoding
        AAAAA      Meaning of one
                   continued here
        B C D E F  Spaced code
        - 4 -
        Part II - Coding
        AAAAA      Meaning in two
      TXT
    end

    it 'runs the preface from the TSB note to the Part I heading' do
      lines = text.lines.map(&:rstrip)
      start = sh.prose_start(lines, 'E')
      expect(start).to eq(0)
      expect(lines[sh.prose_stop(lines, start)]).to start_with('Part I')
    end

    it 'keys a code by part, joins wrapped meanings and removes code spaces' do
      expect(pairs(sh.rows(text))).to eq([['I:AAAAA', 'Meaning of one continued here'], ['I:BCDEF', 'Spaced code'],
                                          ['II:AAAAA', 'Meaning in two']])
    end
  end

  describe 'PpRes21Countries' do
    subject(:sh) { shape('PpRes21Countries') }

    let(:text) do
      <<~TXT
        Note from TSB
        Preface.
        Countries/  Numbers
        2   Zimbabwe                      1   Albania
        - 2 -
        3   Côte d'Ivoire
      TXT
    end

    it 'ends the preface at the country list header' do
      lines = text.lines.map(&:rstrip)
      expect(lines[sh.prose_stop(lines, 0)]).to start_with('Countries/')
    end

    it 'reads two columns per line, keys by name, text is the number, sorted by name' do
      expect(pairs(sh.rows(text))).to eq([['Albania', '1'], ["Côte d'Ivoire", '3'], ['Zimbabwe', '2']])
    end

    it 'returns no rows without the list header' do
      expect(sh.rows("1   Albania\n")).to eq([])
    end
  end

  describe 'M1400CarrierCodes' do
    subject(:sh) { shape('M1400CarrierCodes') }

    let(:text) do
      <<~TXT
        List of ITU Carrier Codes
        Country or area               Company                 Code
        Albania (Republic of) / ALB   Albtelecom              ALB01
                                      Rruga 1
        Barbados / BRB Cable and Wireless   BRB02
                                            Bridgetown
        Annex to ITU OB 1000 - 5 -
        Chile / CHL                   Entel                   CHL03
                                      21-24-26 Calle Uno
      TXT
    end

    it 'ends the preface at the Country or area header' do
      lines = text.lines.map(&:rstrip)
      expect(lines[sh.prose_stop(lines, 0)]).to start_with('Country or area')
    end

    it 'makes one bag-of-words row per company keyed by ISO code, keeping street numbers' do
      rows = sh.rows(text)
      expect(rows.map(&:key)).to eq(%w[ALB BRB CHL])
      expect(rows[0].reading(0, 0)).to eq('albania albtelecom alb alb01 of republic rruga 1'.split.sort.join(' '))
      expect(rows[2].text).to include('21-24-26')
    end

    it 'reads a cell as a country start only within the left margin' do
      indented = "   Albania (Republic of) / ALB   X   A1\n"
      expect(sh.rows(indented).map(&:key)).to eq(%w[ALB])
      expect(sh.rows("          Albania / ALB   X\n")).to eq([])
    end
  end
end
