# frozen_string_literal: true

require 'spec_helper'
require 'ituob/verifiers'

RSpec.describe Ituob::Verifiers::LocalizationAuditor do
  DatasetRepo = Struct.new(:data_by_slug) do
    def each_slug
      data_by_slug.keys.each { |s| yield s }
    end

    def read_data(slug)
      data_by_slug[slug]
    end
  end

  def auditor(data)
    described_class.new(dataset_repository: DatasetRepo.new({ 'test' => data }))
  end

  it 'reports full coverage when all required languages present' do
    data = { 'name' => { 'en' => 'Test', 'fr' => 'Test', 'es' => 'Test' } }
    result = auditor(data).verify
    expect(result.stats[:total_fields]).to eq(1)
    expect(result.stats[:full_coverage]).to eq(1)
    expect(result.stats[:missing_required]).to eq(0)
  end

  it 'reports missing required languages' do
    data = { 'name' => { 'en' => 'Test', 'fr' => 'Test' } }
    result = auditor(data).verify
    expect(result.stats[:full_coverage]).to eq(0)
    expect(result.stats[:missing_required]).to eq(1)
  end

  it 'walks nested hashes' do
    data = {
      'outer' => {
        'inner' => { 'en' => 'A', 'fr' => 'A', 'es' => 'A' },
        'other' => { 'en' => 'B', 'fr' => 'B', 'es' => 'B' },
      },
    }
    result = auditor(data).verify
    expect(result.stats[:total_fields]).to eq(2)
    expect(result.stats[:full_coverage]).to eq(2)
  end

  it 'walks arrays' do
    data = {
      'items' => [
        { 'en' => 'X', 'fr' => 'X', 'es' => 'X' },
        { 'en' => 'Y' },
      ],
    }
    result = auditor(data).verify
    expect(result.stats[:total_fields]).to eq(2)
    expect(result.stats[:full_coverage]).to eq(1)
    expect(result.stats[:missing_required]).to eq(2)
  end

  it 'calculates coverage percentage' do
    data = { 'name' => { 'en' => 'Test', 'fr' => 'Test', 'es' => 'Test' } }
    result = auditor(data).verify
    expect(result.stats[:coverage_pct]).to eq(100.0)
  end

  it 'warns when coverage is below 99%' do
    data = { 'name' => { 'en' => 'Test' } }
    result = auditor(data).verify
    expect(result.warnings).not_to be_empty
  end

  it 'handles empty repository' do
    result = described_class.new(dataset_repository: DatasetRepo.new({})).verify
    expect(result.stats[:total_fields]).to eq(0)
    expect(result.stats[:coverage_pct]).to eq(100.0)
  end
  it 'accepts optional languages without requiring them' do
    data = { 'name' => { 'en' => 'T', 'fr' => 'T', 'es' => 'T', 'ru' => 'T', 'zh' => 'T' } }
    result = auditor(data).verify
    expect(result.stats[:full_coverage]).to eq(1)
  end
end
