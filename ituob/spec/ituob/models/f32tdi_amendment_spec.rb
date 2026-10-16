# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

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

  describe 'notes' do
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
