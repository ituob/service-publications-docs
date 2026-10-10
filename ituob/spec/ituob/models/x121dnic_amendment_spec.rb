# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::X121DNICAmendment do
  def text_node(text)
    { 'type' => 'text', 'text' => text }
  end

  def paragraph(*texts)
    { 'type' => 'paragraph', 'content' => texts.map { |t| text_node(t) } }
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

  def header_row(wording)
    row(cell(paragraph('Country/Area')), cell(paragraph('DNIC No.')),
        cell(paragraph("Name of network to which a DNIC is #{wording}")))
  end

  def parse(doc)
    described_class.parse(doc)
  end

  describe 'change lines' do
    it 'keeps the full P-line text as description' do
      doc = document(paragraph('P 14    Japan    REP all information by:'))
      action = parse(doc).actions.first

      expect(action.position).to eq('P 14')
      expect(action.country).to eq('Japan')
      expect(action.action_type).to eq('REP')
      expect(action.description).to eq('P 14 Japan REP all information by:')
    end

    it 'captures the DNIC printed on the P line as the position' do
      doc = document(paragraph('P    206 6    SUP'))
      action = parse(doc).actions.first

      expect(action.position).to eq('P 206 6')
      expect(action.action_type).to eq('SUP')
    end

    it 'captures a multi-DNIC list line' do
      doc = document(paragraph('206 1, 206 2, 206 4 and 206 9       SUP'))
      action = parse(doc).actions.first

      expect(action.action_type).to eq('SUP')
      expect(action.description).to include('206 1, 206 2')
    end

    it 'reads country-line forms without a P marker' do
      doc = document(paragraph('SENEGAL LIR'))
      action = parse(doc).actions.first

      expect(action.country).to eq('SENEGAL')
      expect(action.action_type).to eq('LIR')
    end
  end

  describe 'table parsing' do
    it 'keeps the printed header wording as the caption' do
      doc = document(
        paragraph('P    206 6    SUP'),
        table(
          header_row('withdrawn'),
          row(cell(paragraph('1')), cell(paragraph('2')), cell(paragraph('3'))),
          row(cell(paragraph('SUÈDE SWEDEN SUECIA')), cell(paragraph('240 2')),
              cell(paragraph('WM-data Infrastructur'))),
        ),
      )
      action = parse(doc).actions.first

      expect(action.caption).to include('withdrawn')
      expect(action.entries.length).to eq(1)
      expect(action.entries.first.network_name).to eq('WM-data Infrastructur')
    end

    it 'splits a trilingual one-line country cell' do
      doc = document(
        paragraph('P    206 6    SUP'),
        table(
          header_row('allocated'),
          row(cell(paragraph('1')), cell(paragraph('2')), cell(paragraph('3'))),
          row(cell(paragraph('BELGIQUE BELGIUM BÉLGICA')), cell(paragraph('206 6')),
              cell(paragraph('Unisource Belgium X.25 Service'))),
        ),
      )
      country = parse(doc).actions.first.entries.first.country_or_area

      expect(country.fr).to eq('BELGIQUE')
      expect(country.en).to eq('BELGIUM')
      expect(country.es).to eq('BÉLGICA')
    end

    it 'fills language slots from country-only rows' do
      doc = document(
        paragraph('United States   ADD'),
        table(
          header_row('allocated'),
          row(cell(paragraph('1')), cell(paragraph('2')), cell(paragraph('3'))),
          row(cell(paragraph('ÉTATS-UNIS')), cell(paragraph('310 0')), cell(paragraph('EMARCONI'))),
          row(cell(paragraph('UNITED STATES')), cell(paragraph('')), cell(paragraph(''))),
          row(cell(paragraph('ESTADOS UNIDOS')), cell(paragraph('')), cell(paragraph(''))),
        ),
      )
      entries = parse(doc).actions.first.entries
      country = entries.first.country_or_area

      expect(entries.length).to eq(1)
      expect(country.fr).to eq('ÉTATS-UNIS')
      expect(country.en).to eq('UNITED STATES')
      expect(country.es).to eq('ESTADOS UNIDOS')
    end

    it 'moves cell paragraphs beyond the three languages into the entry note' do
      doc = document(
        paragraph('P 13 216 1 SUP'),
        table(
          header_row('allocated'),
          row(cell(paragraph('HONGRIE'), paragraph('HUNGARY'), paragraph('HUNGRÍA'),
                    paragraph('1) use internally')),
              cell(paragraph('216 1')), cell(paragraph('Packet Switched Data Service 1)'))),
        ),
      )
      entry = parse(doc).actions.first.entries.first

      expect(entry.country_or_area.en).to eq('HUNGARY')
      expect(entry.note).to eq('1) use internally')
    end
  end

  describe 'notes' do
    it 'collects annex references, see-also paragraphs, and text after ____' do
      doc = document(
        paragraph('(Annex to ITU Operational Bulletin No. 977 – 1.IV.2011) (Amendment No. 8)'),
        paragraph('206 1, 206 2    SUP'),
        paragraph('____________'),
        paragraph('See also pages 4-5 of this ITU Operational Bulletin No. 1129.'),
        paragraph('trailing text'),
      )
      amendment = parse(doc)

      expect(amendment.notes.length).to eq(3)
      expect(amendment.notes.first).to start_with('(Annex')
      expect(amendment.notes).to include(a_string_starting_with('See also pages 4-5'))
    end
  end
end
