# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Ituob::Normalizers::ActionSplitter do
  it 'preserves already separated action files and their printed metadata' do
    Dir.mktmpdir do |root|
      repo = Ituob::Repositories::IssueRepository.new(source_root: root, output_root: root)
      first = { 'type' => 'ADD', 'data' => { 'entries' => [{ 'cc_ic' => '+882 50' }], 'notes' => ['* 22.VIII.2019'] } }
      second = { 'type' => 'SUP', 'data' => { 'entries' => [{ 'cc_ic' => '+882 15' }], 'notes' => ['** 19.I.2022'] } }
      repo.write_change_object('1238', 'e164-cc', '001-ADD.yaml', first)
      repo.write_change_object('1238', 'e164-cc', '002-SUP.yaml', second)

      described_class.new(issue_repository: repo).apply_to('1238')

      expect(repo.read_change_object('1238', 'e164-cc', '001-ADD.yaml')).to eq(first)
      expect(repo.read_change_object('1238', 'e164-cc', '002-SUP.yaml')).to eq(second)
    end
  end

  it 'still splits entries whose embedded action differs from their file action' do
    Dir.mktmpdir do |root|
      repo = Ituob::Repositories::IssueRepository.new(source_root: root, output_root: root)
      repo.write_change_object('1238', 'e164-cc', '001-ADD.yaml',
                               { 'type' => 'ADD', 'data' => { 'entries' => [
                                 { 'country' => 'Norway SUP' }, { 'country' => 'Sweden ADD' },
                               ] } })
      described_class.new(issue_repository: repo).apply_to('1238')
      files = Dir.glob(File.join(root, '1238', 'e164-cc', '*.yaml'))
      changes = files.map { |file| YAML.load_file(file) }
      expect(changes.map { |change| change['type'] }).to contain_exactly('SUP', 'ADD')
      expect(changes.flat_map { |change| change.dig('data', 'entries') }).to contain_exactly(
        { 'country' => 'Norway' }, { 'country' => 'Sweden' })
    end
  end
end
