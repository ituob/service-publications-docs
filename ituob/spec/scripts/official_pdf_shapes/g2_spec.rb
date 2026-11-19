# frozen_string_literal: true

require 'spec_helper'

require File.expand_path('../../../../scripts/compare_official_pdf', __dir__)

# Rows and prose bounds of the code-table shapes (E.212A/B, E.218, Q.708A/B) on
# small `pdftotext -layout` fixtures; no PDF is read.
RSpec.describe 'OfficialPdfComparison code-table shapes' do
  def shape(name) = OfficialPdfComparison.shape(name)

  def pairs(rows) = rows.map { |r| [r.key, r.text] }

  let(:preface) do
    <<~TXT
      Note from TSB

      1.   This list replaces the old one.
      2.   Comments go to the Director.

      Annex to ITU OB 1117-E                         – 2 –
    TXT
  end

  describe 'CodeCountry (E.212A, E.218)' do
    let(:text) do
      <<~TXT
        #{preface}
              List of Codes - numerical order
           Code         Country or Geographical Area         Note
            0XX         Reserved                                a
            202         Greece
            204         Netherlands (Kingdom of the)
                        Antilles wrapped line
            901         Shared code
        Annex to ITU OB 1117-E                         – 3 –
              List of Codes - alphabetical order
            206         Belgium
            202         Greece
      TXT
    end

    it 'keys rows by table and code, joins wrapped names and switches to alpha when codes go back' do
      expect(pairs(shape('CodeCountry').rows(text))).to eq(
        [['num:0XX', 'Reserved a'], ['num:202', 'Greece'], ['num:204', 'Netherlands (Kingdom of the) Antilles wrapped line'],
         ['num:901', 'Shared code'], ['alpha:206', 'Belgium'], ['alpha:202', 'Greece']]
      )
    end

    it 'reads a shared-network row after the numeric table' do
      rows = shape('CodeCountry').rows("      202   Greece\n      101   Early\n  Iridium Inc        901 03\n")
      expect(rows.last.key).to eq('shared:901 03')
    end

    it 'ends the preface at the first page break, not at the F.32 table header' do
      lines = text.lines
      shape = shape('CodeCountry')
      start = shape.prose_start(lines, 'E')
      stop = shape.prose_stop(lines, start)
      expect(lines[start].strip).to eq('Note from TSB')
      expect(lines[stop].strip).to start_with('Annex to ITU OB 1117-E')
      expect(lines[start...stop].join).not_to include('Greece')
    end

    it 'finds the Chinese and Russian preface headings and stops at the first code row if the page number is lost' do
      lines = ["cover\n", "电信标准化局说明\n", "1. text\n", "   202    Greece\n"]
      expect(shape('CodeCountry').prose_start(lines, 'C')).to eq(1)
      expect(shape('CodeCountry').prose_stop(lines, 1)).to eq(3)
    end
  end

  describe 'Sanc (Q.708A)' do
    let(:text) do
      <<~TXT
        #{preface}
        Code   Geographical Area or Signalling Network
        5-220   Former Yugoslav Republic
        5-216   Ireland
        5-221   Former Yugoslav Republic
                of Macedonia
        7-001   Liechtenstein
        Annex to ITU OB 1125-E                         – 3 –
        5-216   Ireland
        7-001   Liechtenstein
      TXT
    end

    it 'keeps an unsorted numeric list together and starts the alphabetical one at a code seen before' do
      expect(pairs(shape('Sanc').rows(text))).to eq(
        [['num:5-220', 'Former Yugoslav Republic'], ['num:5-216', 'Ireland'],
         ['num:5-221', 'Former Yugoslav Republic of Macedonia'], ['num:7-001', 'Liechtenstein'],
         ['alpha:5-216', 'Ireland'], ['alpha:7-001', 'Liechtenstein']]
      )
    end

    it 'ends the preface at the page break and recognises "Note by TSB"' do
      lines = ["Note by TSB\n", "1. text\n", "Annex to ITU OB 1125-E   – 2 –\n", "2-000   Liechtenstein\n"]
      expect(shape('Sanc').prose_start(lines, 'E')).to eq(0)
      expect(shape('Sanc').prose_stop(lines, 0)).to eq(2)
    end
  end

  describe 'MccMnc (E.212B)' do
    it 'keys network rows by MCC and MNC under a country heading' do
      text = <<~TXT
        Country or
        Geographical Area        Networks                      MCC + MNC codes

        Afghanistan
                                 AWCC                              412 01
                                 Roshan                            412 20
        Albania
                                 Vodafone                          276 02
      TXT
      expect(pairs(shape('MccMnc').rows(text))).to include(['main:412 01', 'AWCC'], ['main:412 20', 'Roshan'],
                                                           ['main:276 02', 'Vodafone'], ['country:Afghanistan', 'Afghanistan'])
    end

    it 'reads the Arabic 901 table in the code column as shared rows, not main rows' do
      text = <<~TXT
        أفغانستان
              412 01                                       AWCC
              412 20                                       Roshan
              412 30                                       Etisalat
        ألبانيا
              276 02                                       Vodafone
            901 03                                         Iridium Communications Inc
            901 05                                         Thuraya RMSS Network
      TXT
      got = pairs(shape('MccMnc').rows(text))
      expect(got).to include(['shared:901 03', 'Iridium Communications Inc'], ['shared:901 05', 'Thuraya RMSS Network'],
                             ['main:276 02', 'Vodafone'])
      expect(got.map(&:first)).not_to include('main:901 03')
    end

    it 'ends the preface at the first page break' do
      lines = ["Note from TSB\n", "1. text\n", "Annex to ITU OB 1162-E  – 2 –\n", "                         AWCC       412 01\n"]
      expect(shape('MccMnc').prose_stop(lines, 0)).to eq(2)
    end
  end

  describe 'Ispc (Q.708B)' do
    it 'keys rows by ISPC and sorts the words of DEC, name and operator' do
      text = <<~TXT
        Afghanistan
        4-001-0   1024   Kabul gateway   AWCC
        4-001-1   1025   Herat           Roshan
      TXT
      rows = shape('Ispc').rows(text)
      expect(rows.map(&:key)).to include('4-001-0', '4-001-1')
      expect(rows.find { |r| r.key == '4-001-0' }.text).to eq('1024 AWCC Kabul gateway')
    end

    it 'ends the preface at the first ISPC row when the page number is mangled' do
      lines = ["Note from TSB\n", "1. text\n", "4-001-0   1024   Kabul   AWCC\n"]
      expect(shape('Ispc').prose_stop(lines, 0)).to eq(2)
    end
  end
end
