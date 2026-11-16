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
    {
      'Germany / DEU' => ['Germany', 'DEU', nil],
      'Germany / DEU ADD' => ['Germany', 'DEU', 'ADD'],
      'P 28 to P 29 Germany / DEU ADD' => ['Germany', 'DEU', 'ADD'],
      'P 28 Germany / DEU ADD' => ['Germany', 'DEU', 'ADD'],
      'Germany/DEU ADD' => ['Germany', 'DEU', 'ADD'],
      'Germany /DEU ADD' => ['Germany', 'DEU', 'ADD'],
      'Germany / DEU ADD   ' => ['Germany', 'DEU', 'ADD'],
      '  Germany / DEU ADD' => ['Germany', 'DEU', 'ADD']
    }.each do |heading, expected|
      ['paragraph', 'single-cell table'].each do |shape|
        it "parses #{shape} heading #{heading.inspect}" do
          nodes = if shape == 'paragraph'
                    [paragraph(heading), table(company_row('Email: a@b.net'))]
                  else
                    [table(row(cell(paragraph(heading))), company_row('Email: a@b.net'))]
                  end
          amendment = described_class.parse(doc(*nodes))
          action = amendment.actions.first
          entry = action.entries.first

          expect([entry.country_or_area.en, entry.iso_code, action.action_type]).to eq(expected)
        end
      end
    end

    ['paragraph', 'single-cell table'].each do |shape|
      it "accepts a no-slash country heading in a #{shape}" do
        nodes = if shape == 'paragraph'
                  [paragraph('Germany DEU ADD'), table(company_row('Email: a@b.net'))]
                else
                  [table(row(cell(paragraph('Germany DEU ADD'))), company_row('Email: a@b.net'))]
                end
        amendment = described_class.parse(doc(*nodes))
        entry = amendment.actions.first.entries.first

        expect([entry.country_or_area.en, entry.iso_code, amendment.actions.first.action_type])
          .to eq(['Germany', 'DEU', 'ADD'])
      end
    end

    it 'parses a heading in the only nonempty cell of a multi-cell row' do
      amendment = described_class.parse(
        doc(table(row(cell(paragraph('Germany DEU ADD')), cell(paragraph("\u00a0")), cell), company_row('Email: a@b.net')))
      )
      action = amendment.actions.first
      entry = action.entries.first

      expect([entry.country_or_area.en, entry.iso_code, action.action_type]).to eq(['Germany', 'DEU', 'ADD'])
    end

    ['paragraph', 'single-cell table'].each do |shape|
      it "accepts a starred action in a #{shape}" do
        nodes = if shape == 'paragraph'
                  [paragraph('Germany DEU ADD*'), table(company_row('Email: a@b.net'))]
                else
                  [table(row(cell(paragraph('Germany DEU ADD*'))), company_row('Email: a@b.net'))]
                end
        amendment = described_class.parse(doc(*nodes))
        entry = amendment.actions.first.entries.first

        expect([entry.country_or_area.en, entry.iso_code, amendment.actions.first.action_type])
          .to eq(['Germany', 'DEU', 'ADD*'])
      end
    end

    ['Germany DEU XYZ', 'Germany D3U ADD', 'DEU ADD'].each do |heading|
      ['paragraph', 'single-cell table'].each do |shape|
        it "keeps the company entry for invalid #{shape} heading #{heading.inspect}" do
          nodes = if shape == 'paragraph'
                    [paragraph(heading), table(company_row('Email: a@b.net'))]
                  else
                    [table(row(cell(paragraph(heading))), company_row('Email: a@b.net'))]
                  end
          amendment = described_class.parse(doc(*nodes))
          entries = amendment.actions.flat_map(&:entries)

          if shape == 'paragraph'
            company_entry = entries.find { |entry| entry.company_name == 'Timo Jung Streamworx' }
            expect([company_entry.country_or_area&.en, company_entry.iso_code, amendment.actions.first.action_type])
              .to eq([nil, nil, nil])
          else
            expect(entries.map(&:company_name)).to include(heading, 'Timo Jung Streamworx')
            company_entry = entries.find { |entry| entry.company_name == 'Timo Jung Streamworx' }
            expect([company_entry.country_or_area&.en, company_entry.iso_code]).to eq([nil, nil])
          end
        end
      end
    end

    it 'keeps a multi-column data row when its joined text ends in the ISO action' do
      amendment = described_class.parse(
        doc(paragraph('Germany / DEU ADD'),
            table(row(cell(paragraph('Example Company ')), cell(paragraph('DEU ')), cell(paragraph('ADD')))))
      )
      entry = amendment.actions.first.entries.first

      expect([entry.country_or_area.en, entry.iso_code, entry.company_name, entry.carrier_code, entry.contact])
        .to eq(['Germany', 'DEU', 'Example Company', 'DEU', 'ADD'])
    end

    it 'keeps Palau as the country when an invalid no-slash table heading precedes the company row' do
      amendment = described_class.parse(
        doc(paragraph('Palau / PLW ADD'),
            table(row(cell(paragraph('Germany DEU XYZ')), cell, cell), company_row('Email: a@b.net')))
      )
      entries = amendment.actions.first.entries
      entry = entries.find { |candidate| candidate.company_name == 'Timo Jung Streamworx' }

      expect(entries.map(&:company_name)).to include('Germany DEU XYZ', 'Timo Jung Streamworx')
      expect([entry.country_or_area.en, entry.iso_code]).to eq(['Palau', 'PLW'])
    end

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
