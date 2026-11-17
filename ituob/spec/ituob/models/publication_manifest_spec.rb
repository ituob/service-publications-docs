# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Ituob::Models::PublicationManifest do
  let(:entry_class) { Ituob::Models::PublicationManifestEntry }
  let(:entries) do
    [
      entry_class.new(
        standard: 'E.212B', recommendation: 'E.212', title: 'Mobile Network Codes (MNC)', edition_year: 2018,
        language: 'en', as_of_issue: 1162, sha256: 'a' * 64, status: 'candidate',
        register_slugs: %w[e212-mnc e212-shared-mcc], path: 'pdf/E.212B-2018/E.212B-2018-E.pdf'
      ),
      entry_class.new(
        standard: 'PP.RES.21', recommendation: 'PP.RES.21', title: 'Call-Back', edition_year: 2011,
        language: 'fr', as_of_issue: 991, sha256: 'b' * 64, status: 'itu-adopted',
        register_slugs: [], path: 'pdf/PP.RES.21-2011/PP.RES.21-2011-F.pdf'
      )
    ]
  end
  let(:manifest) { described_class.new(publications: entries) }

  it 'serializes to { "publications": [...] } with the exact keys the site reads' do
    doc = JSON.parse(manifest.to_json)
    expect(doc.keys).to eq(['publications'])
    expect(doc['publications'].first.keys).to eq(
      %w[standard recommendation title edition_year language as_of_issue sha256 status register_slugs path]
    )
    expect(doc['publications'].first).to include('edition_year' => 2018, 'as_of_issue' => 1162)
  end

  it 'keeps an empty register_slugs array in the JSON' do
    expect(JSON.parse(manifest.to_json)['publications'].last['register_slugs']).to eq([])
  end

  it 'round-trips through JSON without loss' do
    back = described_class.from_json(manifest.to_json)
    expect(back).to eq(manifest)
    expect(back.publications.map(&:register_slugs)).to eq([%w[e212-mnc e212-shared-mcc], []])
    expect(back.to_json).to eq(manifest.to_json)
  end

  it 'rejects a status outside candidate / itu-adopted' do
    bad = entry_class.new(standard: 'X', status: 'official')
    expect { bad.validate! }.to raise_error(Lutaml::Model::ValidationError)
  end
end
