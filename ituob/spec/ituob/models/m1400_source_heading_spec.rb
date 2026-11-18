# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'date'
require 'ituob/models'

RSpec.describe 'M1400 source document headings' do
  [
    ['1022', 'Kabel Deutschland Vertrieb & Service GmbH', 'Germany (Federal Republic of)', 'DEU'],
    ['1028', 'CTS (Gibraltar) Limited', 'Gibraltar', 'GIB'],
    ['1028', 'MTX Connect S.a r.l', 'Luxembourg', 'LUX']
  ].each do |issue, company, country, iso|
    it "parses the source document country for #{issue}/#{company}" do
      path = File.expand_path("../../../../itu-ob-data/issues/#{issue}/amendments.yaml", __dir__)
      messages = YAML.safe_load_file(path, permitted_classes: [Date, Time], aliases: true).fetch('messages')
      entries = messages.select { |message| message.dig('target', 'publication') == 'M1400_ICC' }
        .flat_map do |message|
          Ituob::Models::M1400Amendment.parse(message.dig('contents', 'en')).actions.flat_map(&:entries)
        end.select { |entry| entry.company_name == company }

      expect(entries).not_to be_empty
      expect(entries.map { |entry| [entry.country_or_area&.en, entry.iso_code] }.uniq).to eq([[country, iso]])
    end
  end
end
