# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

# The merged continuation rows (address, Tel, Fax, E-mail folded into the carrier
# entry) must not cost an entry its printed country, page position, or the
# separation of its telephone and fax numbers.
RSpec.describe 'M.1400 change files keep printed country, position and tel/fax split' do
  root = File.expand_path('../../../..', __dir__)
  row = lambda do |path|
    data = YAML.safe_load_file(File.join(root, path), permitted_classes: [Date, Time], aliases: true).fetch('data')
    data['entries'] ? data['entries'].first : data
  end

  {
    'datasets/1060-M.1400/changes/1022-0001-ADD-KDVS.yaml' => ['DEU', 'Germany (Federal Republic of)', nil],
    'datasets/1060-M.1400/changes/1028-0001-SUP-GIBCS.yaml' => ['GIB', 'Gibraltar', '+350 216 51500'],
    'datasets/1060-M.1400/changes/1086-0008-ADD-CROSS.yaml' => ['LUX', 'Luxembourg', '+352 43 31 11'],
    'datasets/1060-M.1400/changes/1086-0009-ADD-ELUX.yaml' => ['LUX', 'Luxembourg', nil],
    'ob-issues/1028/m1400-icc/001-SUP.yaml' => ['GIB', 'Gibraltar', '+350 216 51500'],
    'ob-issues/1086/m1400-icc/008-ADD.yaml' => ['LUX', 'Luxembourg', '+352 43 31 11']
  }.each do |path, (iso, country, tel)|
    it "keeps #{path}" do
      entry = row.call(path)
      expect(entry['iso_code']).to eq(iso)
      expect(entry.dig('country_or_area', 'en')).to eq(country)
      expect(entry['tel']).to eq(tel) if tel
      expect([entry['tel'], entry['fax']].compact.join).not_to match(/(?:Fax|Tel)\b\.?\s*:/i)
    end
  end

  it 'keeps the printed page position of OB 1022 KDVS' do
    data = YAML.safe_load_file(File.join(root, 'datasets/1060-M.1400/changes/1022-0001-ADD-KDVS.yaml')).fetch('data')
    expect(data['position']).to eq('P 28')
  end
end
