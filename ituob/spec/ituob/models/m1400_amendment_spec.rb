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
    it 'keeps a padded ISO row as company data while preserving the prior action' do
      padded_row = 'Germany (Federal Republic of) /     DEU'
      amendment = described_class.parse(
        doc(paragraph('Germany (Federal Republic of) / DEU ADD'),
            table(row(cell(paragraph(padded_row)), cell, cell),
                  company_row('Email: a@b.net')))
      )
      entries = amendment.actions.flat_map(&:entries)
      action = amendment.actions.find { |candidate| candidate.entries.length == 2 }

      expect(entries.map(&:company_name)).to eq([padded_row, 'Timo Jung Streamworx'])
      expect(entries.map { |entry| [entry.country_or_area&.en, entry.iso_code] })
        .to eq([['Germany (Federal Republic of)', 'DEU'], ['Germany (Federal Republic of)', 'DEU']])
      expect(action&.action_type).to eq('ADD')
    end

    ['Country or area/ISO code ADD', 'Notes and/or updates ADD'].each do |heading|
      it "does not replace country context with #{heading.inspect}" do
        prior_note = parse('Germany / DEU ADD', 'Email: a@b.net').actions.first.note
        amendment = described_class.parse(
          doc(paragraph('Germany / DEU ADD'), paragraph(heading), table(company_row('Email: a@b.net')))
        )
        action = amendment.actions.find { |candidate| candidate.entries.any? }
        entry = action.entries.first

        expect([entry.country_or_area.en, entry.iso_code, action.action_type, action.note])
          .to eq(['Germany', 'DEU', 'ADD', prior_note])
      end
    end

    it 'keeps the action for a translated label of the same ISO country' do
      amendment = described_class.parse(
        doc(paragraph('Germany (República Federal de) / DEU ADD'),
            table(row(cell(paragraph('Germany (Federal Republic of) / DEU')), cell, cell),
                  company_row('Email: a@b.net')))
      )
      action = amendment.actions.find { |candidate| candidate.entries.any? }
      entry = action.entries.first

      expect([entry.country_or_area.en, entry.iso_code, action.action_type])
        .to eq(['Germany (Federal Republic of)', 'DEU', 'ADD'])
    end

    ['Country or area/ISO ADD', 'Country or area/ISO REP all information by:'].each do |heading|
      it "does not map generic heading title #{heading.inspect}" do
        amendment = described_class.parse(
          doc(paragraph('Germany / DEU ADD'), paragraph(heading), table(company_row('Email: a@b.net')))
        )
        action = amendment.actions.find { |candidate| candidate.entries.any? }
        entry = action.entries.first

        expect([entry.country_or_area.en, entry.iso_code, action.action_type])
          .to eq(['Germany', 'DEU', 'ADD'])
      end
    end

    [
      ['Luxembourg / LUX REP all information by: x / y', 'REP', 'all information by: x / y'],
      ['Luxembourg / LUX DEL x / y', 'DEL', 'x / y'],
      ['Luxembourg / LUX DEL x/y', 'DEL', 'x/y'],
      ['Luxembourg / LUX REP visit https://example.test/a/b', 'REP', 'visit https://example.test/a/b']
    ].each do |heading, action_type, note|
      ['paragraph', 'single-cell table'].each do |shape|
        it "parses #{shape} annotation with slash note #{heading.inspect}" do
          nodes = if shape == 'paragraph'
                    [paragraph('Germany / DEU ADD'), paragraph(heading), table(company_row('Email: a@b.net'))]
                  else
                    [paragraph('Germany / DEU ADD'),
                     table(row(cell(paragraph(heading))), company_row('Email: a@b.net'))]
                  end
          amendment = described_class.parse(doc(*nodes))
          action = amendment.actions.find { |candidate| candidate.entries.any? }
          entry = action.entries.first

          expect([entry.country_or_area.en, entry.iso_code, action.action_type, action.note])
            .to eq(['Luxembourg', 'LUX', action_type, note])
        end
      end
    end

    ['paragraph', 'single-cell table'].each do |shape|
      it "does not infer an ambiguous country from a #{shape} annotated heading" do
        ambiguous_heading = 'Foo / Bar / LUX REP x'
        nodes = if shape == 'paragraph'
                  [paragraph('Germany / DEU ADD'), paragraph(ambiguous_heading), table(company_row('Email: a@b.net'))]
                else
                  [paragraph('Germany / DEU ADD'),
                   table(row(cell(paragraph(ambiguous_heading)), cell, cell), company_row('Email: a@b.net'))]
                end
        amendment = described_class.parse(doc(*nodes))
        entries = amendment.actions.flat_map(&:entries)
        company_entry = entries.find { |entry| entry.company_name == 'Timo Jung Streamworx' }

        expect([company_entry.country_or_area.en, company_entry.iso_code, amendment.actions.first.action_type])
          .to eq(['Germany', 'DEU', 'ADD'])
        expect(entries.map(&:company_name)).to include(ambiguous_heading) if shape == 'single-cell table'
      end
    end

    it 'starts an unannotated Djibouti action after a page-prefixed table heading' do
      amendment = described_class.parse(
        doc(paragraph('Germany / DEU ADD'),
            table(row(cell(paragraph('P 19 Djibouti (Republic of) / DJI')), cell, cell),
                  row(cell(paragraph('Djibouti Company')), cell(paragraph('DJB')),
                      cell(paragraph('Djibouti contact')))))
      )
      action = amendment.actions.find { |candidate| candidate.entries.any? }
      entry = action.entries.first

      expect([entry.country_or_area.en, entry.iso_code, action.action_type, action.note])
        .to eq(['Djibouti (Republic of)', 'DJI', nil, nil])
    end

    it 'does not retroactively change an earlier country action across a table heading' do
      amendment = described_class.parse(
        doc(paragraph('Germany / DEU ADD'),
            table(company_row('Email: a@b.net'),
                  row(cell(paragraph('P 19 Djibouti (Republic of) / DJI')), cell, cell),
                  row(cell(paragraph('Djibouti Company')), cell(paragraph('DJB')),
                      cell(paragraph('Djibouti contact')))))
      )
      actions = amendment.actions.select { |candidate| candidate.entries.any? }

      expect(actions.length).to eq(2)
      expect(actions.map(&:action_type)).to eq(['ADD', nil])
      expect(actions.flat_map(&:entries).map { |entry| [entry.country_or_area.en, entry.iso_code] })
        .to eq([['Germany', 'DEU'], ['Djibouti (Republic of)', 'DJI']])
    end

    it 'keeps the current action for a repeated same-country ISO row' do
      amendment = described_class.parse(
        doc(paragraph('Germany / DEU ADD'),
            table(row(cell(paragraph('Germany / DEU')), cell, cell), company_row('Email: a@b.net')))
      )
      action = amendment.actions.find { |candidate| candidate.entries.any? }

      expect(action.entries.map(&:company_name)).to eq(['Timo Jung Streamworx'])
      expect([action.entries.first.country_or_area.en, action.entries.first.iso_code, action.action_type])
        .to eq(['Germany', 'DEU', 'ADD'])
    end

    it 'starts a new unannotated action for an unprefixed different-country table heading' do
      amendment = described_class.parse(
        doc(paragraph('Germany / DEU ADD'),
            table(row(cell(paragraph('Djibouti (Republic of) / DJI')), cell, cell),
                  row(cell(paragraph('Djibouti Company')), cell(paragraph('DJB')),
                      cell(paragraph('Djibouti contact')))))
      )
      action = amendment.actions.find { |candidate| candidate.entries.any? }

      expect([action.entries.first.country_or_area.en, action.entries.first.iso_code, action.action_type])
        .to eq(['Djibouti (Republic of)', 'DJI', nil])
    end

    [
      ['P 28 Luxembourg / LUX REP all information by:', 'Luxembourg', 'LUX', 'REP', 'all information by:', 'P 28'],
      ['P 28 to P 29 Luxembourg / LUX REP all information by:', 'Luxembourg', 'LUX', 'REP',
       'all information by:', 'P 28'],
      ['  P 28 Luxembourg / LUX REP all information by:', 'Luxembourg', 'LUX', 'REP', 'all information by:', 'P 28'],
      ['  P 28 to P 29 Luxembourg / LUX REP all information by:', 'Luxembourg', 'LUX', 'REP',
       'all information by:', 'P 28'],
      ['P 59 Germany DEU ADD', 'Germany', 'DEU', 'ADD', nil, 'P 59'],
      ['P 59 to P 60 Germany DEU ADD', 'Germany', 'DEU', 'ADD', nil, 'P 59'],
      ['  P 59 Germany DEU ADD', 'Germany', 'DEU', 'ADD', nil, 'P 59'],
      ['  P 59 to P 60 Germany DEU ADD', 'Germany', 'DEU', 'ADD', nil, 'P 59']
    ].each do |heading, country, iso_code, action_type, note, position|
      it "keeps page prefix out of country for #{heading.inspect}" do
        amendment = parse(heading, 'Email: a@b.net')
        action = amendment.actions.first
        entry = action.entries.first

        expect([entry.country_or_area.en, entry.iso_code, action.action_type, action.note])
          .to eq([country, iso_code, action_type, note])
        expect(action.position).to eq(position)
      end
    end

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

    {
      'Luxembourg / LUX REP all information by:' => ['Luxembourg', 'LUX', 'all information by:'],
      'Bosnia and Herzegovina / BIH REP all information by' =>
        ['Bosnia and Herzegovina', 'BIH', 'all information by'],
      'Luxembourg / LUX REP replace ADD' => ['Luxembourg', 'LUX', 'replace ADD']
    }.each do |heading, expected|
      ['paragraph', 'single-nonempty-cell table'].each do |shape|
        it "parses annotated #{shape} heading #{heading.inspect}" do
          nodes = if shape == 'paragraph'
                    [paragraph('Germany / DEU ADD'), paragraph(heading), table(company_row('Email: a@b.net'))]
                  else
                    [paragraph('Germany / DEU ADD'),
                     table(row(cell(paragraph(heading)), cell(paragraph("\u00a0")), cell),
                           company_row('Email: a@b.net'))]
                  end
          amendment = described_class.parse(doc(*nodes))
          action = amendment.actions.find { |candidate| candidate.entries.any? }
          entry = action.entries.first

          expect([entry.country_or_area.en, entry.iso_code, action.action_type, action.note]).to eq(
            [expected[0], expected[1], 'REP', expected[2]]
          )
        end
      end
    end

    ['paragraph', 'single-nonempty-cell table'].each do |shape|
      it "accepts a starred annotated action in a #{shape}" do
        nodes = if shape == 'paragraph'
                  [paragraph('Germany / DEU ADD'), paragraph('Luxembourg / LUX REP* all information by:'),
                   table(company_row('Email: a@b.net'))]
                else
                  [paragraph('Germany / DEU ADD'),
                   table(row(cell(paragraph('Luxembourg / LUX REP* all information by:')), cell, cell),
                         company_row('Email: a@b.net'))]
                end
        amendment = described_class.parse(doc(*nodes))
        action = amendment.actions.find { |candidate| candidate.entries.any? }
        entry = action.entries.first

        expect([entry.country_or_area.en, entry.iso_code, action.action_type, action.note])
          .to eq(['Luxembourg', 'LUX', 'REP*', 'all information by:'])
      end
    end

    ['Luxembourg / LUX XYZ all information by:', 'Luxembourg / LU9 REP all information by:',
     ' / LUX REP all information by:'].each do |heading|
      ['paragraph', 'single-nonempty-cell table'].each do |shape|
        it "preserves Germany after malformed annotated #{shape} heading #{heading.inspect}" do
          nodes = if shape == 'paragraph'
                    [paragraph('Germany / DEU ADD'), paragraph(heading), table(company_row('Email: a@b.net'))]
                  else
                    [paragraph('Germany / DEU ADD'),
                     table(row(cell(paragraph(heading)), cell, cell), company_row('Email: a@b.net'))]
                  end
          amendment = described_class.parse(doc(*nodes))
          entries = amendment.actions.flat_map(&:entries)
          company_entry = entries.find { |entry| entry.company_name == 'Timo Jung Streamworx' }

          expect([company_entry.country_or_area.en, company_entry.iso_code, amendment.actions.first.action_type])
            .to eq(['Germany', 'DEU', 'ADD'])
          expect(entries.map(&:company_name)).to include('Timo Jung Streamworx')
          expect(entries.map(&:company_name)).to include(heading.strip) if shape == 'single-nonempty-cell table'
        end
      end
    end

    it 'keeps a multi-column row that resembles an annotated heading as company data' do
      amendment = described_class.parse(
        doc(paragraph('Germany / DEU ADD'),
            table(row(cell(paragraph('Luxembourg / ')), cell(paragraph('LUX REP ')),
                      cell(paragraph('all information by:')))))
      )
      entry = amendment.actions.flat_map(&:entries).first

      expect([entry.country_or_area.en, entry.iso_code, entry.company_name, entry.carrier_code, entry.contact])
        .to eq(['Germany', 'DEU', 'Luxembourg /', 'LUX REP', 'all information by:'])
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

    [
      ['Example/DEU', 'CODE', 'ADD', 'Example/DEU'],
      ['Example /DEU', 'CODE', 'ADD', 'Example /DEU'],
      ['Example', '/DEU', '', 'Example'],
      ['Example /D', 'EU', '', 'Example /D']
    ].each do |company, carrier, contact, expected_company|
      it "keeps multi-cell slash row #{company.inspect} #{carrier.inspect} as an entry" do
        amendment = described_class.parse(
          doc(paragraph('Palau / PLW ADD'),
              table(row(cell(paragraph(company)), cell(paragraph(carrier)), cell(paragraph(contact))),
                    company_row('Email: a@b.net')))
        )
        entries = amendment.actions.flat_map(&:entries)
        lookalike = entries.find { |entry| entry.company_name == expected_company }
        action = amendment.actions.find { |candidate| candidate.entries.include?(lookalike) } if lookalike

        expect(entries.length).to eq(2)
        expect([action&.action_type, lookalike&.country_or_area&.en, lookalike&.iso_code,
                lookalike&.company_name, lookalike&.carrier_code, lookalike&.contact])
          .to eq(['ADD', 'Palau', 'PLW', expected_company, carrier.strip, contact.strip])
        actual_company = entries.find { |entry| entry.company_name == 'Timo Jung Streamworx' }
        expect([actual_company&.country_or_area&.en, actual_company&.iso_code]).to eq(['Palau', 'PLW'])
      end
    end

    [
      ['Example /   D', 'EU'],
      ['Example /   DEU extra', 'ADD']
    ].each do |company, carrier|
      it "does not expand legacy heading matching after squeezing #{company.inspect} #{carrier.inspect}" do
        amendment = described_class.parse(
          doc(paragraph('Palau / PLW ADD'),
              table(row(cell(paragraph(company)), cell(paragraph(carrier)), cell),
                    company_row('Email: a@b.net')))
        )
        entries = amendment.actions.flat_map(&:entries)
        lookalike = entries.find { |entry| entry.company_name == company.strip }

        expect(entries.length).to eq(2)
        expect([lookalike&.country_or_area&.en, lookalike&.iso_code, lookalike&.company_name,
                lookalike&.carrier_code])
          .to eq(['Palau', 'PLW', company.strip, carrier.strip])
        actual_company = entries.find { |entry| entry.company_name == 'Timo Jung Streamworx' }
        expect([actual_company&.country_or_area&.en, actual_company&.iso_code]).to eq(['Palau', 'PLW'])
      end
    end

    [
      ['Germany / D', 'EU', nil],
      ['Germany / DEU extra', 'ADD', 'ADD']
    ].each do |company, carrier, expected_action|
      it "keeps canonical multi-cell heading #{company.inspect} #{carrier.inspect}" do
        amendment = described_class.parse(
          doc(table(row(cell(paragraph(company)), cell(paragraph(carrier)), cell),
                    company_row('Email: a@b.net')))
        )
        entries = amendment.actions.flat_map(&:entries)

        expect(entries.map(&:company_name)).to eq(['Timo Jung Streamworx'])
        expect([entries.first.country_or_area.en, entries.first.iso_code, amendment.actions.first.action_type])
          .to eq(['Germany', 'DEU', expected_action])
      end
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

    it 'clears the annotated note when a later paragraph declares a new action' do
      amendment = described_class.parse(
        doc(paragraph('Luxembourg / LUX REP all information by:'),
            paragraph('Germany DEU ADD'),
            table(company_row('Email: a@b.net')))
      )
      action = amendment.actions.find { |candidate| candidate.entries.any? }
      entry = action.entries.first

      expect([entry.country_or_area.en, entry.iso_code, action.action_type, action.note])
        .to eq(['Germany', 'DEU', 'ADD', nil])
    end

    it 'updates the country when a slash heading has no action marker' do
      amendment = described_class.parse(
        doc(paragraph('Germany / DEU ADD'), paragraph('Luxembourg / LUX'),
            table(company_row('Email: a@b.net')))
      )
      action = amendment.actions.find { |candidate| candidate.entries.any? }
      entry = action.entries.first

      expect([entry.country_or_area.en, entry.iso_code, action.action_type]).to eq(['Luxembourg', 'LUX', nil])
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
