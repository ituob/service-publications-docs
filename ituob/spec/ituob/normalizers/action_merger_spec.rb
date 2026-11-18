# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Ituob::Normalizers::ActionMerger do
  it 'merges each matching group while preserving other actions and their notes' do
    Dir.mktmpdir do |root|
      repo = Ituob::Repositories::IssueRepository.new(source_root: root, output_root: root)
      [['001-ADD.yaml', 'ADD', 'q', '+883 5140'], ['002-LIR.yaml', 'LIR', 'p', '+883 190'],
       ['003-ADD.yaml', 'ADD', 'q', '+883 5140'], ['004-LIR.yaml', 'LIR', 'p', '+883 190']].each do |name, type, code, cc|
        repo.write_change_object('1114', 'e164-cc', name,
                                 { 'type' => type, 'identifier' => { 'code' => code },
                                   'data' => { 'entries' => [{ 'cc_ic' => cc }], 'notes' => [code] } })
      end
      normalizer = described_class.new(issue_repository: repo)
      normalizer.apply_to('1114')
      changes = Dir.glob(File.join(root, '1114', 'e164-cc', '*.yaml')).map { |file| YAML.load_file(file) }
      expect(changes.map { |change| change['type'] }).to contain_exactly('ADD', 'LIR')
      expect(changes.map { |change| change.dig('data', 'notes') }).to contain_exactly(['q'], ['p'])
      expect(changes.flat_map { |change| change.dig('data', 'entries') }.map { |entry| entry['cc_ic'] }).to contain_exactly(
        '+883 5140', '+883 5140', '+883 190', '+883 190')
      expect(normalizer.apply_to('1114').files_modified).to eq(0)
    end
  end
end
