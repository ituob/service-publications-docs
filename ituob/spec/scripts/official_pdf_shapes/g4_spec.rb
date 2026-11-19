# frozen_string_literal: true

require 'spec_helper'

require File.expand_path('../../../../scripts/compare_official_pdf', __dir__)

# Small synthetic fixtures (what `pdftotext -layout` prints) for the G4 shapes;
# no PDF is read.
RSpec.describe 'G4 official PDF shapes' do
  def shape(name) = OfficialPdfComparison.shape(name)

  def pairs(rows) = rows.map { |r| [r.key, r.text] }

  def stop_line(shape, text)
    lines = text.lines.map(&:chomp)
    start = shape.prose_start(lines, 'E')
    [start, shape.prose_stop(lines, start), lines]
  end

  describe 'prose_start / prose_stop (G4Prose)' do
    let(:text) do
      <<~TXT
        Cover

        1.1.  Note from TSB
        Some preface words.
        Annex to ITU OB 1000-E      - 2 -
        00000001      Afghanistan
      TXT
    end

    it 'starts at a numbered note heading and stops at the first running head' do
      start, stop, lines = stop_line(shape('T35'), text)
      expect(lines[start]).to include('Note from TSB')
      expect(lines[stop]).to start_with('Annex to ITU OB')
    end

    it 'returns the empty range for a PDF without the note' do
      lines = ['Nothing here', 'Annex to ITU OB 1']
      sh = shape('X121A')
      start = sh.prose_start(lines, 'E')
      expect(start).to eq(lines.size)
      expect(sh.prose_stop(lines, start)).to eq(lines.size)
    end

    it 'finds the French and Spanish notes' do
      sh = shape('T35B')
      expect(sh.prose_start(['x', 'Note du TSB'], 'F')).to eq(1)
      expect(sh.prose_start(['x', 'Nota de la TSB'], 'S')).to eq(1)
    end
  end

  describe 'T35' do
    it 'reads one row per bit code and joins a wrapped country name' do
      text = <<~TXT
        b8 b7 b6 b5 b4 b3 b2 b1    Country
        0  0  0  0  0  0  0  1     Afghanistan
        0  0  0  0  0  0  1  0     Democratic People's Republic of
                                      Korea
        Annex to ITU OB 1000-E
                                      Not a wrap after furniture
        0  0  0  0  0  0  1  1     Albania
      TXT
      expect(pairs(shape('T35').rows(text))).to eq(
        [['00000001', 'Afghanistan'], ['00000010', "Democratic People's Republic of Korea"], ['00000011', 'Albania']]
      )
    end
  end

  describe 'T35B' do
    it 'makes one row per country block and unifies differently wrapped values' do
      a = "\nAFGHANISTAN\n\nAdministration:   Ministry of\n  Communications\nEmail:   a@b.af\n\nALBANIA\n\nAdministration:   Ministry\n"
      b = "\nAFGHANISTAN\n\nAdministration:   Ministry of Communications\nEmail:   a@b.af\n\nALBANIA\n\nAdministration:   Ministry\n"
      rows = shape('T35B').rows(a)
      expect(rows.map(&:key)).to eq(%w[AFGHANISTAN ALBANIA])
      expect(pairs(rows)).to eq(pairs(shape('T35B').rows(b)))
      expect(rows.first.text).to eq('Administration: Ministry of Communications Email: a@b.af')
    end

    it 'drops page furniture from a block' do
      text = "\nALBANIA\n\nAdministration:   Ministry\nAnnex to ITU OB 1000-E  - 3 -\nEmail:   x@y.al\n"
      expect(shape('T35B').rows(text).first.text).to eq('Administration: Ministry Email: x@y.al')
    end
  end

  describe 'SR1' do
    let(:header) { "Country/geographical area\n" }

    it 'reads a block as three name lines plus restriction lines' do
      text = <<~TXT
        #{header}
        Afghanistan
        Afghanistan
        Afganistán
        No incoming telex.

        Albanie
        Albania
        Albania
        None.
      TXT
      rows = shape('SR1').rows(text)
      expect(pairs(rows)).to eq(
        [['Afghanistan', 'Afghanistan Afganistán No incoming telex.'], ['Albanie', 'Albania Albania None.']]
      )
    end

    it 'joins a name stub left at a page foot to the chunk after the page break' do
      text = <<~TXT
        #{header}
        Bulgarie
        Bulgaria
        Annex to ITU OB 1000-E   - 5 -
        #{header}

        Bulgaria
        Restriction text that is long enough to be a sentence.

        Chine
        China
        China
        None.
      TXT
      rows = shape('SR1').rows(text)
      expect(rows.map(&:key)).to eq(%w[Bulgarie Chine])
      expect(rows.first.text).to eq('Bulgaria Bulgaria Restriction text that is long enough to be a sentence.')
    end

    it 'does not join a chunk after a page break when the previous chunk is a full block' do
      text = <<~TXT
        #{header}
        Albanie
        Albania
        Albania
        None.
        Annex to ITU OB 1000-E   - 5 -

        Chine
        China
        China
        None.
      TXT
      expect(shape('SR1').rows(text).map(&:key)).to eq(%w[Albanie Chine])
    end

    it 'ends the preface at the table header when no running head comes first' do
      lines = ['Note from TSB', 'words', 'Country/geographical area', 'rows']
      sh = shape('SR1')
      expect(sh.prose_stop(lines, 0)).to eq(2)
    end

    it 'accepts a "1.1." prefixed note' do
      expect(shape('SR1').prose_start(['x', '1.1. Note from TSB'], 'E')).to eq(1)
    end
  end

  describe 'X121A' do
    it 'reads three digit codes and joins an indented wrapped name' do
      text = <<~TXT
        202   Greece
        204   Netherlands (Kingdom of the) - Aruba and the
              other territories
        Annex to ITU OB 1000-E
              Not a wrap
        206   Belgium
      TXT
      expect(pairs(shape('X121A').rows(text))).to eq(
        [['202', 'Greece'], ['204', 'Netherlands (Kingdom of the) - Aruba and the other territories'], ['206', 'Belgium']]
      )
    end

    it 'ignores summary lines without a code column' do
      expect(shape('X121A').rows("Zone 2, number of codes in reserve  4\n")).to be_empty
    end
  end

  describe 'X121B' do
    it 'reads a DNIC with a network name that wraps under the network column' do
      text = <<~TXT
        Greece       202 1   Hellenic Telecommunications
                                Organization
        Hellas       202 5   OTE Datanet
      TXT
      expect(pairs(shape('X121B').rows(text))).to eq(
        [['202 1', 'Hellenic Telecommunications Organization'], ['202 5', 'OTE Datanet']]
      )
    end

    it 'keeps multi-digit and ranged codes as one key' do
      text = "Zone      230 40-44    Network A\nOther     260 621      Network B\n"
      expect(shape('X121B').rows(text).map(&:key)).to eq(['230 40-44', '260 621'])
    end

    it 'treats a code that starts a line as a row' do
      expect(pairs(shape('X121B').rows("302 11   Teleglobe\n"))).to eq([['302 11', 'Teleglobe']])
    end

    it 'does not take running lower-case words after a lone code for a network name' do
      expect(shape('X121B').rows("302 11   see the note below\n")).to be_empty
    end

    it 'takes a wrap line the generated PDF prints in the network column after country text' do
      text = "Greece       202 1   Hellenic Telecom\nHellas               Organization\n"
      expect(shape('X121B').rows(text).first.text).to eq('Hellenic Telecom Organization')
    end
  end

  describe 'RR251' do
    let(:head) do
      <<~TXT
        Administration                                  Permitted  Forbidden  Note  Pages
                         1      2     3     4      5
      TXT
    end

    it 'reads which column the x is in, the remark note and the pages' do
      text = <<~TXT
        #{head}
        Albania ............   x                    1)    4
        Korea (Dem. People's
          Rep. of) .........                x            7-8
      TXT
      rows = shape('RR251').rows(text)
      expect(pairs(rows)).to eq(
        [['Albania', 'permitted note pages 4'], ["Korea (Dem. People's Rep. of)", 'forbidden pages 7-8']]
      )
    end

    it 'uses the leftmost x per page as the permitted column, so a drifted page still reads right' do
      text = <<~TXT
        #{head}
        Albania ............                      x
        Annex to ITU OB 1000-E
        #{head}
        Algeria ............   x
        Angola .............                   x
      TXT
      rows = shape('RR251').rows(text)
      expect(pairs(rows)).to eq([['Albania', 'permitted'], ['Algeria', 'permitted'], ['Angola', 'forbidden']])
    end

    it 'does not count an x one column right of the permitted x as forbidden (FORBIDDEN_GAP)' do
      text = "#{head}\nAlbania ............   x\nAlgeria ............    x\n"
      expect(shape('RR251').rows(text).map(&:text)).to eq(%w[permitted permitted])
    end

    it 'joins a wrapped administration name' do
      text = "#{head}\nUnited Kingdom of Great Britain and\n  Northern Ireland ....   x\n"
      expect(shape('RR251').rows(text).map(&:key)).to eq(['United Kingdom of Great Britain and Northern Ireland'])
    end

    it 'reads the call sign forms of part 2, one block per administration' do
      text = <<~TXT
        #{head}
        Albania ............   x
        ________________
        2.  Forms of call signs
        2.1.  Albania
        ZA, 11A-11Z

        2.2.  Algeria
        7R
      TXT
      rows = shape('RR251').rows(text)
      expect(pairs(rows.select { |r| r.key.start_with?('forms:') })).to eq(
        [['forms: Albania', 'ZA, 11A-11Z 2.2. Algeria 7R']]
      ).or eq([['forms: Albania', 'ZA, 11A-11Z'], ['forms: Algeria', '7R']])
    end
  end
end
