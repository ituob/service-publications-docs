# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'yaml'
require 'ituob/catalogs'
require 'ituob/registers'
require 'ituob/verifiers'

RSpec.describe Ituob::Verifiers::RegisterStateIntegrityVerifier, 'generated snapshots' do
  let(:root) { Dir.mktmpdir('register-state-snapshots') }
  let(:snapshots_root) { File.join(root, 'snapshots') }
  let(:catalog) { Ituob::Catalogs::Registers }
  let(:register) { catalog.find('TEST') }
  let(:current_path) { File.join(snapshots_root, 'test', 'current.json') }
  let(:historical_path) { File.join(snapshots_root, 'test', 'at-1001.json') }
  let(:current_snapshot) { JSON.parse(File.read(current_path)) }
  let(:verifier) { described_class.new(registers_catalog: catalog, root: root, snapshots_root: snapshots_root) }

  before do
    catalog_path = File.join(root, 'registers.yaml')
    File.write(catalog_path, <<~YAML)
      registers:
        - register_id: TEST
          slug: test
          key_field: code
          seed_issue: 1000
          seed_path: datasets/1000-Test
    YAML
    catalog.load!(path: catalog_path)
    dataset = File.join(root, register.seed_path)
    FileUtils.mkdir_p(File.join(dataset, 'changes'))
    File.write(File.join(dataset, 'data.yaml'), [{ 'code' => 'AAA', 'name' => 'Alpha' }].to_yaml)
    File.write(File.join(dataset, 'changes', '1001-ADD.yaml'), {
      'type' => 'ADD', 'register' => 'TEST', 'ob_issue_no' => 1001,
      'identifier' => { 'code' => 'BBB' }, 'data' => { 'code' => 'BBB', 'name' => 'Beta' }
    }.to_yaml)
    states = described_class.build_replay(register, root: root).build_all_states
    Ituob::Registers::SnapshotWriter.new(output_root: snapshots_root).write(
      slug: register.slug, manifest_fields: register.to_h,
      current_state: states.fetch(nil), states_by_issue: states
    )
  end

  after do
    catalog.reset!
    FileUtils.rm_rf(root)
  end

  it 'passes every generated edition and preserves replay counts' do
    result = verifier.verify

    expect(result).to be_passed
    expect(result.errors).to be_empty
    expect(result.stats).to include(registers_checked: 1, states_checked: 3, entries_checked: 5)
    expect(result.details.map { |detail| detail[:ob_issue] }).to contain_exactly(1000, 1001, 'current')
  end

  it 'rejects a corrupted field even when keys and counts still match' do
    expect(verifier.verify).to be_passed
    current_snapshot.fetch('active_entries').first['name'] = 'Corrupted'
    File.write(current_path, JSON.generate(current_snapshot))

    expect(verifier.verify.errors).to contain_exactly(a_string_including('TEST', 'current', current_path, 'snapshot'))
  end

  it 'rejects a dropped entry even when the entry count is corrected' do
    expect(verifier.verify).to be_passed
    current_snapshot.fetch('active_entries').pop
    current_snapshot['entry_count'] = 1
    File.write(current_path, JSON.generate(current_snapshot))

    expect(verifier.verify.errors).to contain_exactly(a_string_including('TEST', 'current', current_path, 'snapshot'))
  end

  %w[active_entries history].each do |field|
    it "rejects reordered #{field}" do
      expect(verifier.verify).to be_passed
      expect(current_snapshot.fetch(field).length).to be > 1
      current_snapshot.fetch(field).reverse!
      File.write(current_path, JSON.generate(current_snapshot))

      expect(verifier.verify.errors).to contain_exactly(a_string_including('TEST', 'current', current_path, 'snapshot'))
    end
  end

  it 'rejects a missing historical edition and identifies its path' do
    expect(verifier.verify).to be_passed
    FileUtils.rm(historical_path)

    expect(verifier.verify.errors).to contain_exactly(a_string_including('TEST', '1001', historical_path, 'snapshot'))
  end

  it 'rejects malformed JSON without aborting verification' do
    expect(verifier.verify).to be_passed
    File.write(current_path, '{broken')

    expect(verifier.verify.errors).to contain_exactly(a_string_including('TEST', 'current', current_path, 'snapshot'))
  end

  it 'rejects a JSON value of the wrong type' do
    expect(verifier.verify).to be_passed
    File.write(current_path, '[]')

    expect(verifier.verify.errors).to contain_exactly(a_string_including('TEST', 'current', current_path, 'snapshot'))
  end

  it 'preserves verification without snapshots when the option is omitted' do
    FileUtils.rm_rf(snapshots_root)

    result = described_class.new(registers_catalog: catalog, root: root).verify

    expect(result).to be_passed
    expect(result.stats).to include(states_checked: 3, entries_checked: 5)
  end
end
