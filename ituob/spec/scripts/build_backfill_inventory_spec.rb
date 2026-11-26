# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require_relative '../../../scripts/build_backfill_inventory'

RSpec.describe Backfill::Inventory do
  let(:held) { { 669 => '1998-06-01', 955 => '2010-05-01T00:00:00.000Z', 967 => '2010-11-01T11:40:24.377Z' } }
  let(:entries) { described_class.classify(held).to_h { |e| [e['number'], e] } }

  it 'classifies held numbers a and everything else unresolved, never b/c/d' do
    expect(entries.size).to eq(1343)
    expect(entries.values.map { |e| e['class'] }.uniq.sort).to eq(%w[a unresolved])
    expect(entries.select { |_, e| e['class'] == 'a' }.keys).to eq([669, 955, 967])
  end

  it 'takes the year of a held issue from publication_date' do
    expect(entries[955]).to include('expected_year' => 2010, 'year_source' => 'publication_date')
  end

  it 'estimates an absent number between two dated held issues' do
    # 955 is 2010-05; 12 issues later is 2010-11, 24 issues later 2011-05
    expect(entries[966]).to include('class' => 'unresolved', 'expected_year' => 2010, 'year_source' => 'estimated')
    expect(entries[961]['expected_year']).to eq(2010)
  end

  it 'estimates below 669 backwards at 24 issues a year' do
    # 669 is 1998-06; 24 issues earlier is 1997-06, 669 issues earlier (no. 1) about 1970
    expect(entries[645]).to include('expected_year' => 1997, 'year_source' => 'estimated')
    expect(entries[1]['expected_year']).to eq(1970)
  end
end

RSpec.describe BuildBackfillInventory do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:inventory) { YAML.safe_load(described_class.build(root))['inventory'] }

  it 'has 1343 entries with one class each and class a exactly the held set' do
    expect(inventory.map { |e| e['number'] }).to eq((1..1343).to_a)
    held = [669] + (955..965).to_a + (967..1343).to_a
    expect(held.size).to eq(389)
    expect(inventory.select { |e| e['class'] == 'a' }.map { |e| e['number'] }).to eq(held)
    expect(inventory.reject { |e| e['class'] == 'a' }.map { |e| e['class'] }.uniq).to eq(['unresolved'])
  end

  it 'is byte-identical on a rerun and matches the committed file' do
    first = described_class.build(root)
    expect(described_class.build(root)).to eq(first)
    expect(File.read(File.join(root, 'docs/backfill/inventory.yaml'))).to eq(first)
  end
end
