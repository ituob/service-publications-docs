# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::M1400Amendment do
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

  def doc(*nodes)
    { 'type' => 'doc', 'content' => nodes }
  end

  def company_row(email_line)
    row(
      cell(paragraph('Timo Jung Streamworx'), paragraph('Edisonstrasse 63')),
      cell(paragraph('STWX')),
      cell(paragraph('Mr. Timo Jung'),
           paragraph("Tel.:    +49 30 863221 380"),
           paragraph("Fax:    +49 30 863221 381"),
           paragraph(email_line))
    )
  end

  def parse(heading, email_line)
    described_class.parse(doc(paragraph(heading), table(company_row(email_line))))
  end

  describe 'country heading' do
    it 'keeps the whole country name and the ISO code as the position' do
      heading = "Germany (Federal Republic of) / DEU     ADD"
      amendment = parse(heading, 'Email: a@b.net')

      expect(amendment.actions.first.position).to eq('Germany (Federal Republic of) / DEU')
      expect(amendment.actions.first.action_type).to eq('ADD')
    end

    it 'keeps a single-word country with its ISO code' do
      amendment = parse('Palau / PLW ADD', 'E-mail: a@b.net')

      expect(amendment.actions.first.position).to eq('Palau / PLW')
    end

    it 'keeps the ISO code when the heading prints no action marker' do
      entry = parse('P 22 Equatorial Guinea (Republic of) / GNQ', 'E-mail: a@b.net').actions.first.entries.first

      expect([entry.country_or_area.en, entry.iso_code]).to eq(['Equatorial Guinea (Republic of)', 'GNQ'])
    end

    it 'drops a page range marker from the country' do
      entry = parse('P 28 to P 29 Germany (Federal Republic of) / DEU ADD', 'E-mail: a@b.net').actions.first.entries.first

      expect(entry.country_or_area.en).to eq('Germany (Federal Republic of)')
    end

    it 'does not feed the entry country from the position' do
      entry = parse('Germany (Federal Republic of) / DEU ADD', 'E-mail: a@b.net').actions.first.entries.first

      expect([entry.country_or_area.en, entry.iso_code]).to eq(['Germany (Federal Republic of)', 'DEU'])
    end
  end

  describe 'email' do
    ["E-mail: a@b.net", "Email:    a@b.net", 'email: a@b.net'].each do |label|
      it "is read from the label variant #{label.inspect}" do
        entry = parse('Germany / DEU ADD', label).actions.first.entries.first

        expect(Array(entry.email)).to eq(['a@b.net'])
      end
    end

    it 'leaves email empty when none is printed' do
      entry = described_class.parse(doc(paragraph('Germany / DEU ADD'),
                                        table(row(cell(paragraph('Co')), cell(paragraph('X')),
                                                  cell(paragraph('Mr A'), paragraph('Tel: 1'))))))
                             .actions.first.entries.first

      expect(Array(entry.email)).to be_empty
    end
  end
end
