# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'date'

RSpec.describe 'Generated M1400 country headings' do
  [
    ['1022', 'Kabel Deutschland Vertrieb & Service GmbH', 'Germany (Federal Republic of)', 'DEU'],
    ['1028', 'CTS (Gibraltar) Limited', 'Gibraltar', 'GIB'],
    ['1028', 'MTX Connect S.a r.l', 'Luxembourg', 'LUX']
  ].each do |issue, company, country, iso|
    it "preserves the printed country and ISO in #{issue}/#{company}" do
      paths = Dir.glob(File.expand_path("../../../../ob-issues/#{issue}/m1400-icc/*.yaml", __dir__))
      entries = paths.flat_map do |path|
        YAML.safe_load_file(path, permitted_classes: [Date, Time], aliases: true).fetch('data').fetch('entries')
      end.select { |entry| entry['company_name'] == company }

      expect(entries).not_to be_empty
      expect(entries.map { |entry| [entry.dig('country_or_area', 'en'), entry['iso_code']] }.uniq)
        .to eq([[country, iso]])
    end
  end
end
