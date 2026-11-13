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
    end
  end
end
