# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Ituob::Normalizers::KeyWhitespace do
  let(:printed) { "Printed\u00a0text" }

  it 'cleans stored keys and codes while preserving typography and is idempotent' do
    Dir.mktmpdir do |root|
      repo = Ituob::Repositories::IssueRepository.new(source_root: root, output_root: root)
      original = {
        'type' => 'ADD', 'identifier' => { 'code' => "P\u00a019" },
        'description' => printed,
        'data' => {
          'country' => { 'en' => "United\u00a0States" },
          'caption' => printed, 'notes' => [printed],
          'entries' => [{ 'country' => { 'en' => "United\u00a0States", 'fr' => "Etats\u00a0Unis" },
                          'code' => ["12\u00a034"], 'contact_name' => printed }],
        },
      }
      repo.write_change_object('1000', 't35-na', '001-ADD.yaml', original)
      repo.write_change_object('1000', 't35-na', 'text.yaml', { 'contents' => printed })
      normalizer = described_class.new(issue_repository: repo)

      expect(normalizer.apply_to('1000').files_modified).to eq(1)
      patch = repo.read_change_object('1000', 't35-na', '001-ADD.yaml')
      expect(patch['identifier']).to eq('code' => 'P 19')
      expect(patch.dig('data', 'country')).to eq('en' => 'United States')
      expect(patch.dig('data', 'entries', 0, 'country')).to eq('en' => 'United States', 'fr' => 'Etats Unis')
      expect(patch.dig('data', 'entries', 0, 'code')).to eq(['12 34'])
      expect(patch.dig('data', 'entries', 0, 'contact_name')).to eq(printed)
      expect(patch.dig('data', 'notes')).to eq([printed])
      expect(patch.dig('data', 'caption')).to eq(printed)
      expect(patch['description']).to eq(printed)
      expect(repo.read_change_object('1000', 't35-na', 'text.yaml')).to eq('contents' => printed)
      expect(normalizer.apply_to('1000').files_modified).to eq(0)
    end
  end

  it 'uses the catalog primary and fallback keys for every register' do
    Ituob::Catalogs::Registers.all.each do |register|
      fields = [register.key_field, register.fallback_key_fields].flatten.compact
      row = fields.to_h { |field| [field, "12\u00a034"] }
      patch = { 'data' => { 'entries' => [row] } }
      cleaned = described_class.clean_patch(patch, register.amendment_slug)
      expect(cleaned.dig('data', 'entries', 0)).to eq(fields.to_h { |field| [field, '12 34'] })
      expect(patch.dig('data', 'entries', 0)).to eq(row)
    end
  end
  it 'merges NBSP-equivalent identifiers on the first pipeline run' do
    Dir.mktmpdir do |root|
      repo = Ituob::Repositories::IssueRepository.new(source_root: root, output_root: root)
      ["P\u00a019", 'P 19'].each_with_index do |code, index|
        repo.write_change_object('1000', 'e212-mnc', format('%03d-ADD.yaml', index + 1),
          { 'type' => 'ADD', 'identifier' => { 'code' => code },
            'data' => { 'entries' => [{ 'mcc_mnc_codes' => "208 0#{index + 1}" }] } })
      end
      pipeline = Ituob::Normalizers::Pipeline.new(issue_repository: repo)
      pipeline.run
      files = Dir.glob(File.join(root, '1000/e212-mnc/*.yaml'))
      expect(files.size).to eq(1)
      patch = repo.read_change_object('1000', 'e212-mnc', File.basename(files.first))
      expect(patch.dig('data', 'entries').map { |row| row['mcc_mnc_codes'] }).to eq(['208 01', '208 02'])
      expect(pipeline.run).to all(be_empty)
    end
  end

end
