# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::F400Amendment do
  ['', " \t ", " \u00a0 "].each do |blank|
    context "with a #{blank.inspect} separator row" do
      let(:rows) do
        [
          ['France', 'ADMD-FR', 'FR', 'MT-fr', 'IPM-fr', '', 'help-fr', 'auto-fr', 'Contact FR'],
          Array.new(9, blank),
          ['France EN', '', '', '', '', '', '', '', 'Address continued'],
          ['Francia', '', '', '', '', '', '', '', ''],
          ['Allemagne', 'ADMD-DE', 'DE', 'MT-de', 'IPM-de', '', 'help-de', 'auto-de', 'Contact DE']
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
          ['Contact FR', 'Address continued'],
          ['Contact DE']
        ])
        expect(entries.map(&:mt)).to eq(['MT-fr', 'MT-de'])
        expect(entries.map(&:ipm)).to eq(['IPM-fr', 'IPM-de'])
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
      expect(entry.mt).to eq('SPAIRAL-MT')
      expect(entry.ipm).to eq('SPAIRAL-IPM')
      expect(entry.helpdesk).to be_nil
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
        expect(entries.first.helpdesk[:x400]).to eq('6')
        expect(entries.first.autoanswer[:x400]).to eq('7')
        expect(entries.first.contact_address[:address_lines]).to eq(['Addr'])
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

    it 'stacks the HELPDESK, AUTOANSWER and contact columns across the fr/en/es rows' do
      expect(entries.first.helpdesk[:x400]).to eq("S= helpdesk\nA=viat\nC=de")
      expect(entries.first.autoanswer[:x400]).to eq("S=autoanswer\nA=viat\nC=de")
      expect(entries.first.contact_address[:address_lines]).to eq(['Ralf Knecht'])
    end

    it 'keeps every printed non-empty data cell somewhere in its entry' do
      survivors = entries.flat_map do |e|
        [e.admd_name, e.country_code, e.country_or_area.fr, e.country_or_area.en, e.country_or_area.es,
         e.mt, e.ipm, e.other, e.helpdesk&.dig(:x400), e.autoanswer&.dig(:x400),
         *e.contact_address[:address_lines]].compact.flat_map { |v| v.split("\n") }
      end
      printed = rows.drop(4).flatten.reject { |c| c.strip.empty? || c == nb }

      expect(printed - survivors).to be_empty
    end

    it 'keeps the stacked fr/en/es service names under their MT and IPM columns' do
      expect(entries.first.mt).to eq("BusinessMail\nMailGate\nX.400 MT")
      expect(entries.first.ipm).to eq("BusinessMail\nMailbox\nX.400 - IPM")
      expect(entries.first.other).to be_nil
    end
  end

  describe 'rows and cells the parser must not drop' do
    def parse_rows(rows)
      cell = ->(text) { { 'type' => 'table_cell', 'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }] } }
      document = { 'type' => 'doc', 'content' => [
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'P 1 ADD' }] },
        { 'type' => 'table', 'content' => rows.map { |r| { 'type' => 'table_row', 'content' => r.map(&cell) } } }
      ] }
      described_class.parse(document).actions.first.entries
    end

    let(:first_row) { ['France', 'ADMD-FR', 'FR', 'm1', 'i1', 'o1', 'h1', 'a1', 'c1'] }
    let(:nameless_row) { ['', 'AD2', 'DE', 'm2', 'i2', 'o2', 'h2', 'a2', 'c2'] }

    it 'starts a new entry for a nameless-country row with an ADMD and code after an entry' do
      entries = parse_rows([first_row, nameless_row])

      expect(entries.map(&:admd_name)).to eq(%w[ADMD-FR AD2])
      expect(entries.map(&:country_code)).to eq(%w[FR DE])
      expect(entries.last.country_or_area.fr).to be_nil
      expect(entries.last.mt).to eq('m2')
    end

    it 'keeps a nameless-country row as the first data row' do
      entries = parse_rows([nameless_row])

      expect(entries.map(&:admd_name)).to eq(%w[AD2])
      expect(entries.first.contact_address[:address_lines]).to eq(['c2'])
    end

    it 'keeps country names beyond the third row' do
      entries = parse_rows([first_row, ['English'] + [''] * 8, ['Espanol'] + [''] * 8, ['Extra'] + [''] * 8])

      expect(entries.first.country_or_area.es).to eq('Espanol')
      expect(entries.first.note).to eq('Extra')
    end

    it 'keeps a non-empty cell past the ninth column with the contact lines' do
      entries = parse_rows([first_row + ['tenth']])

      expect(entries.first.contact_address[:address_lines]).to eq(%w[c1 tenth])
    end

    it 'keeps digits-only ADMD and code cells of a nameless-country row in the note' do
      entries = parse_rows([first_row, ['', '400', '1', 'm2', '', '', '', '', '']])

      expect(entries.size).to eq(1)
      expect(entries.first.note).to eq("400\n1")
      expect(entries.first.mt).to eq("m1\nm2")
    end

    it 'keeps a continuation-looking row that opens the table' do
      entries = parse_rows([['', '', '49', 'm2', 'i2', '', '', '', 'c2']])

      expect(entries.size).to eq(1)
      expect(entries.first.note).to eq('49')
      expect(entries.first.mt).to eq('m2')
      expect(entries.first.contact_address[:address_lines]).to eq(['c2'])
    end

    it 'leaves a blank ADMD name nil' do
      entries = parse_rows([['DE', '', 'DE']])

      expect(entries.first.admd_name).to be_nil
      expect(entries.first.country_code).to eq('DE')
    end
  end
end
