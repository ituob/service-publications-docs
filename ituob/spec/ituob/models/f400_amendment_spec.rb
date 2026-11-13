# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::F400Amendment do
  ['', " \t ", " \u00a0 "].each do |blank|
    context "with a #{blank.inspect} separator row" do
      let(:rows) do
        [
          ['France', 'ADMD-FR', 'FR', 'MT', 'help-fr', 'auto-fr', 'Paris', 'Street 1', 'Contact FR'],
          Array.new(9, blank),
          ['France EN', '', '', '', '', '', 'Address continued', '', ''],
          ['Francia', '', '', '', '', '', '', '', ''],
          ['Allemagne', 'ADMD-DE', 'DE', 'MT', 'help-de', 'auto-de', 'Berlin', 'Street 2', 'Contact DE']
        ]
      end
      let(:document) do
        {
          'type' => 'doc',
          'content' => [
            { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'P 1 ADD' }] },
            { 'type' => 'table', 'content' => rows.map do |row|
              { 'type' => 'table_row', 'content' => row.map do |cell|
                { 'type' => 'table_cell', 'content' => [
                  { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => cell }] }
                ] }
              end }
            end }
          ]
        }
      end

      it 'ignores the blank row and preserves the surrounding entries and continuations' do
        entries = described_class.parse(document).actions.first.entries

        expect(entries.map(&:admd_name)).to eq(['ADMD-FR', 'ADMD-DE'])
        expect(entries.map(&:country_code)).to eq(['FR', 'DE'])
        expect(entries.map { |entry| entry.country_or_area.fr }).to eq(['France', 'Allemagne'])
        expect(entries.first.country_or_area.en).to eq('France EN')
        expect(entries.first.country_or_area.es).to eq('Francia')
        expect(entries.last.country_or_area.en).to be_nil
        expect(entries.map { |entry| entry.helpdesk[:x400] }).to eq(['help-fr', 'help-de'])
        expect(entries.map { |entry| entry.autoanswer[:x400] }).to eq(['auto-fr', 'auto-de'])
        expect(entries.map { |entry| entry.contact_address[:address_lines] }).to eq([
          ['Paris', 'Street 1', 'Contact FR', 'Address continued'],
          ['Berlin', 'Street 2', 'Contact DE']
        ])
      end

      it 'preserves Spanish when the blank row separates English and Spanish continuations' do
        rows[1], rows[2] = rows[2], rows[1]

        entries = described_class.parse(document).actions.first.entries

        expect(entries.map(&:admd_name)).to eq(['ADMD-FR', 'ADMD-DE'])
        expect(entries.first.country_or_area.en).to eq('France EN')
        expect(entries.first.country_or_area.es).to eq('Francia')
        expect(entries.last.country_or_area.fr).to eq('Allemagne')
      end
    end
  end

  context 'with the OB 1193 Spain ADD table shape' do
    let(:nbsp) { "\u00a0" }
    let(:rows) do
      [
        [nbsp] * 7,
        %w[Country ADMD\ Name Country\ code Service\ Name(s) HELPDESK AUTOANSWER Contact\ Address],
        [nbsp] * 7,
        [nbsp, nbsp, nbsp, 'MT', 'IPM', 'other', nbsp, nbsp, nbsp],
        %w[1 2 3 4 5 6 7 8 9],
        [nbsp] * 9,
        ['Espagne', 'SPAIRAL', 'ES', 'SPAIRAL-MT', 'SPAIRAL-IPM', nbsp, '', '', 'SPAIRAL COMMERCE S.L. Logrono'],
        ['Spain', nbsp, nbsp, nbsp, nbsp, nbsp, nbsp, nbsp],
        ['España', nbsp, nbsp, nbsp, nbsp, nbsp, nbsp, nbsp],
        [nbsp] * 9
      ]
    end
    let(:document) do
      cell = lambda do |text|
        { 'type' => 'table_cell', 'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }] }
      end
      { 'type' => 'doc', 'content' => [
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => "P 18  Spain  ADD" }] },
        { 'type' => 'table', 'content' => rows.map { |r| { 'type' => 'table_row', 'content' => r.map(&cell) } } }
      ] }
    end

    it 'keeps only the SPAIRAL allocation, never layout, header or column-number rows' do
      entries = described_class.parse(document).actions.first.entries

      expect(entries.length).to eq(1)
      entry = entries.first
      expect(entry.admd_name).to eq('SPAIRAL')
      expect(entry.country_code).to eq('ES')
      expect(entry.country_or_area.fr).to eq('Espagne')
      expect(entry.country_or_area.en).to eq('Spain')
      expect(entry.country_or_area.es).to eq('España')
      expect(entry.helpdesk[:x400]).to eq('SPAIRAL-IPM')
      expect(entry.contact_address[:address_lines]).to eq(['SPAIRAL COMMERCE S.L. Logrono'])
      expect(entries.map(&:admd_name).join).not_to match(/\A\s*\z|\A\d+\z/)
    end
  end

  context 'with layout and continuation row variants' do
    let(:real) { ['Espagne', 'SPAIRAL', 'ES', 'SPAIRAL-MT', 'SPAIRAL-IPM', '', '', '', 'Addr'] }
    let(:document) do
      cell = lambda do |text|
        content = text.empty? ? [{ 'type' => 'paragraph' }] : [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }]
        { 'type' => 'table_cell', 'content' => content }
      end
      { 'type' => 'doc', 'content' => [
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'P 18  Spain  ADD' }] },
        { 'type' => 'table', 'content' => rows.map { |r| { 'type' => 'table_row', 'content' => r.map(&cell) } } }
      ] }
    end
    let(:entries) { described_class.parse(document).actions.first.entries }

    context 'when the column-number row has a trailing blank cell (OB 989)' do
      let(:rows) { [%w[1 2 3 4 5 6 7 8 9] + [''], real] }

      it 'skips it as layout' do
        expect(entries.map(&:admd_name)).to eq(['SPAIRAL'])
      end
    end

    context 'when the column-number row has a hole' do
      let(:rows) { [['1', '2', '3', '', '5', '6', '7', '8', '9'], real] }

      it 'skips it as layout' do
        expect(entries.map(&:admd_name)).to eq(['SPAIRAL'])
      end
    end

    context 'when a continuation row has only MT in the fourth cell' do
      let(:rows) { [real, ['', '', '', 'MT', '', '', '', '', '']] }

      it 'keeps it as a continuation row without leaking the service label into the address' do
        expect(entries.length).to eq(1)
        expect(entries.first.contact_address[:address_lines]).to eq(['Addr'])
      end
    end

    context 'when the column-number row has one leading blank cell (OB 1006)' do
      let(:rows) { [[''] + %w[1 2 3 4 5 6 7 8 9], real] }

      it 'skips it as layout' do
        expect(entries.map(&:admd_name)).to eq(['SPAIRAL'])
      end
    end

    context 'when a continuation row holds a few numeric cells' do
      let(:rows) do
        [real, ['', '', '', '', '', '', '6', '7', ''], ['', '1', '2', '', '', '', '', '', ''],
         ['', '', '', '', '4', '5', '', '', '']]
      end

      it 'keeps them as continuation data' do
        expect(entries.length).to eq(1)
        expect(entries.first.contact_address[:address_lines]).to include('6', '7')
      end
    end

    context 'when the MT/IPM sub-header is shifted one column left (OB 1006)' do
      let(:rows) { [real, ['', '', 'MT', 'IPM', 'other', '', '', '', '']] }

      it 'skips it as layout' do
        expect(entries.first.contact_address[:address_lines]).to eq(['Addr'])
      end
    end

    context 'when a continuation row has MT next to non-service text' do
      let(:rows) { [real, ['', '', '', 'MT', '4', '', '', '', '']] }

      it 'treats it as a continuation row without leaking MT or a new entry' do
        expect(entries.length).to eq(1)
        expect(entries.first.contact_address[:address_lines]).to eq(['Addr'])
      end
    end
  end

  context 'with the OB 1092 German block shape (en/es rows carry service labels)' do
    let(:nb) { "\u00a0" }
    let(:rows) do
      [
        [nb] * 9,
        [nb, nb, nb, 'MT', 'IPM', 'other', nb, nb, nb],
        %w[1 2 3 4 5 6 7 8 9],
        [nb] * 9,
        ['Allemagne', 'DBP', 'DE', 'BusinessMail', 'BusinessMail', '', 'S= helpdesk', 'S=autoanswer', 'Ralf Knecht'],
        ['Germany', '', '', 'MailGate', 'Mailbox', '', 'A=viat', 'A=viat', ''],
        ['Alemania', '', '', 'X.400 MT', 'X.400 - IPM', '', 'C=de', 'C=de', ''],
        [nb] * 9,
        ['Allemagne', 'VIAT', 'DE', 'BusinessMail', 'BusinessMail', '', 'S=helpdesk', 'S=autoanswer', 'Ralf Knecht'],
        ['Germany', '', '', 'MailGate', 'Mailbox', '', 'A=viat', 'A=viat', ''],
        ['Alemania', '', '', 'X.400 - MT', 'X.400 - IPM', '', 'C=de', 'C=de', '']
      ]
    end
    let(:document) do
      cell = lambda do |text|
        { 'type' => 'table_cell',
          'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }] }
      end
      { 'type' => 'doc', 'content' => [
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'P 4  ADD' }] },
        { 'type' => 'table', 'content' => rows.map { |r| { 'type' => 'table_row', 'content' => r.map(&cell) } } }
      ] }
    end
    let(:entries) { described_class.parse(document).actions.first.entries }

    it 'yields one entry per ADMD block with fr/en/es country names' do
      expect(entries.map(&:admd_name)).to eq(%w[DBP VIAT])
      expect(entries.map(&:country_code)).to eq(%w[DE DE])
      expect(entries.map { |e| [e.country_or_area.fr, e.country_or_area.en, e.country_or_area.es] }.uniq)
        .to eq([%w[Allemagne Germany Alemania]])
    end

    it 'keeps the fr-row helpdesk and drops the translated service labels from the address' do
      expect(entries.map { |e| e.helpdesk[:x400] }).to eq(%w[BusinessMail BusinessMail])
      expect(entries.first.contact_address[:address_lines])
        .to eq(['S= helpdesk', 'S=autoanswer', 'Ralf Knecht', 'A=viat', 'A=viat', 'C=de', 'C=de'])
    end
  end
end
