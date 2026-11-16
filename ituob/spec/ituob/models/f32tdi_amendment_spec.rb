# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'
require 'prosereflect'
require 'yaml'

RSpec.describe Ituob::Models::F32TDIAmendment do
  def text_node(text)
    { 'type' => 'text', 'text' => text }
  end

  def paragraph(*texts)
    { 'type' => 'paragraph', 'content' => texts.map { |t| text_node(t) } }
  end

  def hard_break
    { 'type' => 'hard_break' }
  end

  def cell(*paragraphs)
    { 'type' => 'table_cell', 'content' => paragraphs }
  end

  def row(*cells)
    { 'type' => 'table_row', 'content' => cells }
  end

  def table(*rows)
    { 'type' => 'table', 'content' => rows }
  end

  def document(*blocks)
    { 'type' => 'doc', 'content' => blocks }
  end

  def parse(doc)
    described_class.parse(doc)
  end

  describe 'P/COL change lines' do
    it 'builds position from P and COL lines and keeps the change text' do
      doc = document(
        paragraph('P  27   Madagascar       SUP'),
        paragraph('COL  2 REP          GOVT – Société des télécommunications, Antananarivo'),
      )
      amendment = parse(doc)

      expect(amendment.actions.length).to eq(1)
      action = amendment.actions.first
      expect(action.position).to eq('P 27 COL 2')
      expect(action.action_type).to eq('REP')
      expect(action.description).to include('Madagascar')
      expect(action.description).to include('GOVT – Société des télécommunications')
    end

    it 'supports P lines without a printed number' do
      doc = document(paragraph('P      Bahrain    LIR'))
      action = parse(doc).actions.first

      expect(action.position).to eq('P')
      expect(action.action_type).to eq('LIR')
    end

    it 'appends continuation paragraphs ("by ...") to the description' do
      doc = document(
        paragraph('P  41    Yemen    LIR'),
        paragraph('COL  2 REP          TELEYEMEN, Sana’a'),
        paragraph('By Unitel'),
      )
      action = parse(doc).actions.first

      expect(action.description).to include('TELEYEMEN')
      expect(action.description).to include('By Unitel')
    end

    it 'opens a new action per P line' do
      doc = document(
        paragraph('P 3 GERMANY ADD'),
        table(row(cell(paragraph('ALLEMAGNE')), cell(paragraph('ROA')), cell(paragraph('DP')),
                  cell(paragraph('subarea')), cell(paragraph('DPXX')))),
        paragraph('P 27 LITHUANIA SUP'),
        table(row(cell(paragraph('LITUANIE')), cell(paragraph('ROA2')), cell(paragraph('LT')),
                  cell(paragraph('subarea')), cell(paragraph('LTXX')))),
      )
      amendment = parse(doc)

      expect(amendment.actions.length).to eq(2)
      expect(amendment.actions[0].entries.length).to eq(1)
      expect(amendment.actions[1].entries.length).to eq(1)
    end
  end

  describe 'country parsing' do
    def entry_for(country_cell)
      doc = document(
        paragraph('P 1 TEST ADD'),
        table(
          row(cell(paragraph('Country/ geographical Area')), cell(paragraph('Network')),
              cell(paragraph('DI')), cell(paragraph('Office')), cell(paragraph('Code'))),
          row(cell(paragraph('1')), cell(paragraph('2')), cell(paragraph('3')),
              cell(paragraph('4')), cell(paragraph('5'))),
          row(country_cell, cell(paragraph('ROA')), cell(paragraph('CC')),
              cell(paragraph('OFFICE')), cell(paragraph('OCODE'))),
        ),
      )
      parse(doc).actions.first.entries.first
    end

    it 'maps three paragraphs to fr/en/es' do
      entry = entry_for(cell(paragraph('LITUANIE'), paragraph('LITHUANIA'), paragraph('LITUANIA')))

      expect(entry.country_or_area.fr).to eq('LITUANIE')
      expect(entry.country_or_area.en).to eq('LITHUANIA')
      expect(entry.country_or_area.es).to eq('LITUANIA')
    end

    it 'splits a single three-word trilingual line' do
      entry = entry_for(cell(paragraph('ALLEMAGNE'), hard_break, paragraph('GERMANY'),
                             hard_break, paragraph('ALEMANIA')))

      expect(entry.country_or_area.fr).to eq('ALLEMAGNE')
      expect(entry.country_or_area.en).to eq('GERMANY')
      expect(entry.country_or_area.es).to eq('ALEMANIA')
    end

    it 'keeps a two-word single name verbatim in fr' do
      entry = entry_for(cell(paragraph('CÔTE D’IVOIRE')))

      expect(entry.country_or_area.fr).to eq('CÔTE D’IVOIRE')
      expect(entry.country_or_area.en).to be_nil
    end

    ['*', '12)'].each do |marker|
      it "separates the trailing #{marker} country note marker after a long whitespace run" do
        entry = entry_for(cell(paragraph("ITALIE#{' ' * 10_000}#{marker}")))

        expect(entry.country_or_area.fr).to eq('ITALIE')
        expect(entry.country_or_area_note.en).to eq(marker)
      end
    end

    it 'keeps a long numeric country suffix without a closing parenthesis' do
      country = "REGION #{'1' * 10_000}"
      entry = entry_for(cell(paragraph(country)))

      expect(entry.country_or_area.fr).to eq(country)
      expect(entry.country_or_area_note).to be_nil
    end
  end

  describe 'row shape handling' do
    def doc_with_rows(*rows)
      document(paragraph('P 1 TEST ADD'), table(*rows))
    end

    it 'skips header and column-number rows' do
      doc = doc_with_rows(
        row(cell(paragraph('Country/ geographical Area')), cell(paragraph('Network')),
            cell(paragraph('DI')), cell(paragraph('Office')), cell(paragraph('Assigned'))),
        row(cell(paragraph('1')), cell(paragraph('2')), cell(paragraph('3')),
            cell(paragraph('4')), cell(paragraph('5'))),
        row(cell(paragraph('QATAR')), cell(paragraph('Unitel')), cell(paragraph('DH- -')),
            cell(paragraph('All destinations')), cell(paragraph('DHXX'))),
      )
      entries = parse(doc).actions.first.entries

      expect(entries.length).to eq(1)
      expect(entries.first.office_code).to eq('DHXX')
    end

    it 'keeps per-row network values (no cross-row overwrite)' do
      doc = doc_with_rows(
        row(cell(paragraph('ALLEMAGNE')), cell(paragraph('UNITEL ALTEVEER')), cell(paragraph('DP')),
            cell(paragraph('subarea')), cell(paragraph('DPXX'))),
        row(cell(paragraph('')), cell(paragraph('TELEGRAMM SERVICES')), cell(paragraph('DD')),
            cell(paragraph('subarea')), cell(paragraph('DDXX'))),
      )
      entries = parse(doc).actions.first.entries

      expect(entries[0].network_roa).to eq('UNITEL ALTEVEER')
      expect(entries[0].office_code).to eq('DPXX')
      expect(entries[1].network_roa).to eq('TELEGRAMM SERVICES')
      expect(entries[1].office_code).to eq('DDXX')
    end

    it 'inherits country and network on continuation rows' do
      doc = doc_with_rows(
        row(cell(paragraph('BAHREÏN')), cell(paragraph('Unitel')), cell(paragraph('BN- -')),
            cell(paragraph('Bahrain')), cell(paragraph('BNBA'))),
        row(cell(paragraph('')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('Manama')), cell(paragraph('BNMA'))),
      )
      entries = parse(doc).actions.first.entries

      expect(entries[1].country_or_area.fr).to eq('BAHREÏN')
      expect(entries[1].network_roa).to eq('Unitel')
      expect(entries[1].office_code).to eq('BNMA')
    end

    it 'fills empty language slots from country-only rows' do
      doc = doc_with_rows(
        row(cell(paragraph('EGYPTE')), cell(paragraph('Telecom Egypt')), cell(paragraph('UN--')),
            cell(paragraph('15 MAY CITY')), cell(paragraph('UNMY'))),
        row(cell(paragraph('EGYPT')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('EGIPTO')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('ABASIA')), cell(paragraph('UNAB'))),
      )
      entries = parse(doc).actions.first.entries
      country = entries.last.country_or_area

      expect(entries.length).to eq(2)
      expect(country.fr).to eq('EGYPTE')
      expect(country.en).to eq('EGYPT')
      expect(country.es).to eq('EGIPTO')
    end

    it 'starts a new country when a coded row prints its own country and network' do
      doc = doc_with_rows(
        row(cell(paragraph('ESPAGNE 1)')), cell(paragraph('Correos')), cell(paragraph('ES-')),
            cell(paragraph('MADRID')), cell(paragraph('ESMA'))),
        row(cell(paragraph('ESPAGNE')), cell(paragraph('Correos')), cell(paragraph('ES-')),
            cell(paragraph('BARCELONA')), cell(paragraph('ESBX'))),
        row(cell(paragraph('FRANCE')), cell(paragraph('France Telecom')), cell(paragraph('FR-')),
            cell(paragraph('PARIS')), cell(paragraph('FRPA'))),
        row(cell(paragraph('')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('LYON')), cell(paragraph('FRLY'))),
      )
      entries = parse(doc).actions.first.entries
      keys = entries.map { |entry| [entry.country_or_area.fr, entry.network_code, entry.office_code] }

      expect(keys).to eq([
        ['ESPAGNE', 'ES-', 'ESMA'],
        ['ESPAGNE', 'ES-', 'ESBX'],
        ['FRANCE', 'FR-', 'FRPA'],
        ['FRANCE', 'FR-', 'FRLY'],
      ])
      expect(entries.map { |entry| entry.country_or_area.en }).to all(be_nil)
      expect(entries.map { |entry| entry.country_or_area.es }).to all(be_nil)
      expect(entries.first(2).map { |entry| entry.country_or_area_note.en }).to all(eq('1)'))
      expect(entries.drop(2).map(&:country_or_area_note)).to all(be_nil)
      expect(entries.first(2).map(&:network_roa)).to all(eq('Correos'))
      expect(entries.drop(2).map(&:network_roa)).to all(eq('France Telecom'))
    end

    it 'fills language variants across coded rows before starting a complete new country' do
      doc = doc_with_rows(
        row(cell(paragraph('BAHREÏN 1)')), cell(paragraph('Unitel')), cell(paragraph('BN- -')),
            cell(paragraph('Bahrain')), cell(paragraph('BNBA'))),
        row(cell(paragraph('BAHRAIN')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('Manama')), cell(paragraph('BNMA'))),
        row(cell(paragraph('BAHREIN')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('Other destinations')), cell(paragraph('BNAX'))),
        row(cell(paragraph('JORDANIE'), paragraph('JORDAN'), paragraph('JORDANIA')),
            cell(paragraph('Unitel')), cell(paragraph('JO- -')),
            cell(paragraph('Amman')), cell(paragraph('JOAM'))),
        row(cell(paragraph('')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('Jerusalem Jordan')), cell(paragraph('JOJM'))),
      )
      entries = parse(doc).actions.first.entries
      keys = entries.map { |entry| [entry.country_or_area.fr, entry.network_code, entry.office_code] }

      expect(keys).to eq([
        ['BAHREÏN', 'BN- -', 'BNBA'],
        ['BAHREÏN', 'BN- -', 'BNMA'],
        ['BAHREÏN', 'BN- -', 'BNAX'],
        ['JORDANIE', 'JO- -', 'JOAM'],
        ['JORDANIE', 'JO- -', 'JOJM'],
      ])
      expect(entries.first(3).map { |entry| entry.country_or_area.en }).to all(eq('BAHRAIN'))
      expect(entries.first(3).map { |entry| entry.country_or_area.es }).to all(eq('BAHREIN'))
      expect(entries.first(3).map { |entry| entry.country_or_area_note.en }).to all(eq('1)'))
      expect(entries.last(2).map { |entry| entry.country_or_area.en }).to all(eq('JORDAN'))
      expect(entries.last(2).map { |entry| entry.country_or_area.es }).to all(eq('JORDANIA'))
      expect(entries.last(2).map(&:country_or_area_note)).to all(be_nil)
    end

    it 'starts a separate country when a network heading follows another country entry' do
      doc = doc_with_rows(
        row(cell(paragraph('BAHREÏN 1)')), cell(paragraph('Unitel')), cell(paragraph('BN- -')),
            cell(paragraph('Bahrain')), cell(paragraph('BNBA'))),
        row(cell(paragraph('JORDANIE')), cell(paragraph('Unitel')), cell(paragraph('JO- -')),
            cell(paragraph("\u00A0")), cell(paragraph("\u00A0"))),
        row(cell(paragraph('')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('Amman')), cell(paragraph('JOAM'))),
        row(cell(paragraph('')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('Jerusalem Jordan')), cell(paragraph('JOJM'))),
      )
      amendment = parse(doc)
      entries = amendment.actions.first.entries
      keys = entries.map { |entry| [entry.country_or_area.fr, entry.network_code, entry.office_code] }

      expect(keys).to eq([
        ['BAHREÏN', 'BN- -', 'BNBA'],
        ['JORDANIE', 'JO- -', 'JOAM'],
        ['JORDANIE', 'JO- -', 'JOJM'],
      ])
      expect(entries.map { |entry| entry.country_or_area.en }).to all(be_nil)
      expect(entries.first.country_or_area_note.en).to eq('1)')
      expect(entries.drop(1).map(&:country_or_area_note)).to all(be_nil)
      expect(amendment.notes).to include('Unitel — JO- -')
    end

    it 'keeps consecutive language headings together after another country entry' do
      doc = doc_with_rows(
        row(cell(paragraph('BAHREÏN')), cell(paragraph('Unitel')), cell(paragraph('BN- -')),
            cell(paragraph('Bahrain')), cell(paragraph('BNBA'))),
        row(cell(paragraph('ITALIE 1)')), cell(paragraph('Unrouted')), cell(paragraph('IU- -')),
            cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('ITALY 1)')), cell(paragraph('GOVT – Ministry of Economic')), cell(paragraph('IG- -')),
            cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('ITALIA 1)')), cell(paragraph('Development, Roma')), cell(paragraph('')),
            cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('')), cell(paragraph('UTS GmbH 1)')), cell(paragraph('IT- -')),
            cell(paragraph('15011 ACQUI TERME')), cell(paragraph('--AC'))),
      )
      entries = parse(doc).actions.first.entries

      expect(entries.length).to eq(2)
      expect(entries.first.country_or_area.fr).to eq('BAHREÏN')
      expect(entries.first.country_or_area.en).to be_nil
      expect(entries.first.country_or_area.es).to be_nil
      expect(entries.first.country_or_area_note).to be_nil
      expect(entries.last.country_or_area.fr).to eq('ITALIE')
      expect(entries.last.country_or_area.en).to eq('ITALY')
      expect(entries.last.country_or_area.es).to eq('ITALIA')
      expect(entries.last.country_or_area_note.en).to eq('1)')
      expect(entries.last.network_code).to eq('IT- -')
      expect(entries.last.office_code).to eq('--AC')
    end

    it 'uses the country on an uncoded office row for the entries that follow' do
      doc = doc_with_rows(
        row(cell(paragraph('BAHREÏN 1)')), cell(paragraph('Unitel')), cell(paragraph('BN- -')),
            cell(paragraph('Bahrain')), cell(paragraph('BNBA'))),
        row(cell(paragraph('JORDANIE 2)')), cell(paragraph('Unitel')), cell(paragraph('JO- -')),
            cell(paragraph('Amman -->')), cell(paragraph("\u00A0"))),
        row(cell(paragraph('JORDAN')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('Amman')), cell(paragraph('JOAM'))),
        row(cell(paragraph('JORDANIA')), cell(paragraph('')), cell(paragraph('')),
            cell(paragraph('Jerusalem Jordan')), cell(paragraph('JOJM'))),
      )
      amendment = parse(doc)
      entries = amendment.actions.first.entries

      expect(entries.map(&:office_code)).to eq(%w[BNBA JOAM JOJM])
      expect(entries.first.country_or_area.fr).to eq('BAHREÏN')
      expect(entries.first.country_or_area.en).to be_nil
      expect(entries.first.country_or_area_note.en).to eq('1)')
      expect(entries.drop(1).map { |entry| entry.country_or_area.fr }).to all(eq('JORDANIE'))
      expect(entries.drop(1).map { |entry| entry.country_or_area.en }).to all(eq('JORDAN'))
      expect(entries.drop(1).map { |entry| entry.country_or_area.es }).to all(eq('JORDANIA'))
      expect(entries.drop(1).map { |entry| entry.country_or_area_note.en }).to all(eq('2)'))
      expect(entries.drop(1).map(&:network_code)).to all(eq('JO- -'))
      expect(amendment.notes).to include('Unitel — JO- - — Amman -->')
    end

    it 'does not carry a previous data country note into a new data country' do
      doc = doc_with_rows(
        row(cell(paragraph('ITALIE 1)')), cell(paragraph('UTS GmbH 1)')), cell(paragraph('IT- -')),
            cell(paragraph('15011 ACQUI TERME')), cell(paragraph('--AC'))),
        row(cell(paragraph('BAHREÏN'), paragraph('BAHRAIN'), paragraph('BAHREIN')),
            cell(paragraph('Unitel')), cell(paragraph('BN- -')),
            cell(paragraph('Bahrain')), cell(paragraph('BNBA'))),
      )
      entries = parse(doc).actions.first.entries

      expect(entries.first.country_or_area.fr).to eq('ITALIE')
      expect(entries.first.country_or_area_note.en).to eq('1)')
      expect(entries.last.country_or_area.fr).to eq('BAHREÏN')
      expect(entries.last.country_or_area_note).to be_nil
    end

    it 'joins multi-paragraph office code cells' do
      doc = doc_with_rows(
        row(cell(paragraph('ESPAGNE')), cell(paragraph('Correos')), cell(paragraph('ES-')),
            cell(paragraph('BARCELONA')), cell(paragraph('ESBX'), paragraph('ESMX'))),
      )
      entry = parse(doc).actions.first.entries.first

      expect(entry.office_code).to eq('ESBX ESMX')
    end

    it 'carries 7-column numbering-plan rows as notes' do
      doc = doc_with_rows(
        row(cell(paragraph('Myanmar')), cell(paragraph('95')), cell(paragraph('00')),
            cell(paragraph('0')), cell(paragraph('7 to 10 digits')),
            cell(paragraph('+6.30')), cell(paragraph(''))),
      )
      amendment = parse(doc)

      expect(amendment.actions.first.entries).to be_empty
      expect(amendment.notes).to include(a_string_including('Myanmar — 95'))
    end
  end

  describe 'printed headings and notes from real issues' do
    let(:issue_number) { '1017' }
    let(:source) do
      YAML.unsafe_load_file(File.join(FIXTURE_ROOT, issue_number, 'amendments.yaml'))
        .fetch('messages').find { |message| message.dig('target', 'publication') == 'F32_TDI' }
        .dig('contents', 'en')
    end
    let(:amendment) { parse(source) }
    let(:entries) { amendment.actions.flat_map(&:entries) }

    it 'keeps Italy headings and uncoded cross-references out of the office entries (OB 1017)' do
      expect(entries.length).to eq(235)
      key_parts = entries.flat_map do |entry|
        [entry.country_or_area.fr, entry.country_or_area.en, entry.country_or_area.es,
         entry.network_code, entry.office_code]
      end.compact
      expect(entries.map { |entry| entry.country_or_area.fr }).to all(match(/\S/))
      expect(entries.map(&:network_code)).to all(match(/\S/))
      expect(entries.map(&:office_code)).to all(match(/\S/))
      expect(key_parts).to all(satisfy { |part| !part.include?("\u00A0") })
      expect(entries.first.office_code).to eq('--AC')
      expect(entries.first.telegraph_office_name.en).to eq('15011 ACQUI TERME')
      expect(entries.first.network_roa).to eq('UTS GmbH 1)')
      expect(entries.first.country_or_area.fr).to eq('ITALIE')
      expect(entries.first.country_or_area.en).to eq('ITALY')
      expect(entries.first.country_or_area.es).to eq('ITALIA')
      expect(entries.first.country_or_area_note.en).to eq('1)')
      expect(amendment.notes).to include('Unrouted — IU- -',
                                       'GOVT – Ministry of Economic — IG- -',
                                       'Development, Roma', '60100 ANCONE -->', 'ANCONA')
      expect(amendment.notes).to include(a_string_starting_with('* See Note published'))
      expect(entries.last.office_code).to eq('--RX')
    end

    it 'starts fresh country metadata for the next action' do
      doc = document(
        paragraph('P 19 Italy REP'),
        table(
          row(cell(paragraph('ITALIE 1)')), cell(paragraph('UTS GmbH 1)')), cell(paragraph('IT- -')),
              cell(paragraph("\u00A0")), cell(paragraph("\u00A0"))),
          row(cell(paragraph('')), cell(paragraph('')), cell(paragraph('')),
              cell(paragraph('15011 ACQUI TERME')), cell(paragraph('--AC'))),
        ),
        paragraph('P Bahrain LIR'),
        table(row(cell(paragraph('BAHREÏN')), cell(paragraph('Unitel')), cell(paragraph('BN- -')),
                  cell(paragraph('Bahrain')), cell(paragraph('BNBA')))),
      )
      actions = parse(doc).actions

      expect(actions.first.entries.length).to eq(1)
      expect(actions.first.entries.first.country_or_area_note.en).to eq('1)')
      expect(actions.last.entries.length).to eq(1)
      expect(actions.last.entries.first.country_or_area.fr).to eq('BAHREÏN')
      expect(actions.last.entries.first.country_or_area.en).to be_nil
      expect(actions.last.entries.first.country_or_area_note).to be_nil
    end

    context 'with Jordan (OB 1000)' do
      let(:issue_number) { '1000' }

      it 'shares all three country languages and the heading network across real office rows' do
        expect(entries.map(&:office_code)).to eq(%w[JOAM JOJM JOAX])
        expect(entries.map { |entry| entry.country_or_area.fr }).to all(eq('JORDANIE'))
        expect(entries.map { |entry| entry.country_or_area.en }).to all(eq('JORDAN'))
        expect(entries.map { |entry| entry.country_or_area.es }).to all(eq('JORDANIA'))
        expect(entries.map(&:network_roa)).to all(eq('Unitel'))
        expect(entries.map(&:network_code)).to all(eq('JO- -'))
        key_parts = entries.flat_map do |entry|
          [entry.country_or_area.fr, entry.network_code, entry.office_code]
        end
        expect(key_parts).to all(match(/\S/))
        expect(key_parts).to all(satisfy { |part| !part.include?("\u00A0") })
        expect(amendment.notes).to include('Unitel — JO- -')
        expect(amendment.notes).to include(a_string_starting_with('* See Note published'))
      end
    end
  end

  describe 'notes' do
    it 'keeps note-only country cell text on coded rows without replacing the current country' do
      doc = document(
        paragraph('P 3 GERMANY ADD'),
        table(
          row(cell(paragraph('ALLEMAGNE')), cell(paragraph('ROA')), cell(paragraph('DP')),
              cell(paragraph('subarea')), cell(paragraph('DPXX'))),
          row(cell(paragraph('* Country details')), cell(paragraph('ROA2')), cell(paragraph('DP2')),
              cell(paragraph('office')), cell(paragraph('DPYY'))),
        ),
      )
      amendment = parse(doc)
      entries = amendment.actions.first.entries

      expect(entries.last.country_or_area.fr).to eq('ALLEMAGNE')
      expect(entries.last.country_or_area_note).to be_nil
      expect(amendment.notes).to include('* Country details')
    end

    it 'collects note-only country cell text on four-cell rows' do
      doc = document(
        paragraph('P 3 GERMANY ADD'),
        table(
          row(cell(paragraph('ALLEMAGNE')), cell(paragraph('ROA')), cell(paragraph('DP')),
              cell(paragraph('subarea')), cell(paragraph('DPXX'))),
          row(cell(paragraph('* Four-cell note')), cell(paragraph('')), cell(paragraph('')),
              cell(paragraph(''))),
        ),
      )
      amendment = parse(doc)

      expect(amendment.actions.first.entries.first.country_or_area.fr).to eq('ALLEMAGNE')
      expect(amendment.notes).to include('* Four-cell note')
    end

    it 'collects numbered note-only country cell text on shorter country-only rows' do
      doc = document(
        paragraph('P 3 GERMANY ADD'),
        table(
          row(cell(paragraph('ALLEMAGNE')), cell(paragraph('ROA')), cell(paragraph('DP')),
              cell(paragraph('subarea')), cell(paragraph('DPXX'))),
          row(cell(paragraph('1) Country note')), cell(paragraph('')), cell(paragraph(''))),
        ),
      )
      amendment = parse(doc)

      expect(amendment.actions.first.entries.first.country_or_area.fr).to eq('ALLEMAGNE')
      expect(amendment.notes).to include('1) Country note')
    end

    it 'collects 1-cell footnote rows as notes, not countries' do
      doc = document(
        paragraph('P 3 GERMANY ADD'),
        table(
          row(cell(paragraph('Country/ geographical Area')), cell(paragraph('Network')),
              cell(paragraph('DI')), cell(paragraph('Office')), cell(paragraph('Assigned'))),
          row(cell(paragraph('ALLEMAGNE')), cell(paragraph('ROA')), cell(paragraph('DP')),
              cell(paragraph('subarea')), cell(paragraph('DPXX'))),
          row(cell(paragraph('*  This information cancels and replaces that published in ITU OB No. 949'))),
        ),
      )
      amendment = parse(doc)
      entry = amendment.actions.first.entries.first

      expect(entry.country_or_area.fr).to eq('ALLEMAGNE')
      expect(entry.country_or_area.en).to be_nil
      expect(amendment.notes.length).to eq(1)
      expect(amendment.notes.first).to include('cancels and replaces')
    end

    it 'collects Corrigendum and numbered footnote paragraphs' do
      doc = document(
        paragraph('Corrigendum*'),
        paragraph('P 27 LITHUANIA LIR'),
        paragraph('1)    The national and international telegram service is not accepted'),
      )
      amendment = parse(doc)

      expect(amendment.notes).to include(a_string_starting_with('Corrigendum'))
      expect(amendment.notes).to include(a_string_starting_with('1)'))
    end

    it 'treats everything after a ____ separator as notes' do
      doc = document(
        paragraph('P 27 LITHUANIA LIR'),
        paragraph('____________'),
        paragraph('*    This communication cancels and replaces that published'),
        paragraph('trailing free text'),
      )
      amendment = parse(doc)

      expect(amendment.notes.length).to eq(2)
    end
  end
end
