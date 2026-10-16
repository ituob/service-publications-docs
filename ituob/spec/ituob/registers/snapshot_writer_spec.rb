# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'ituob/registers'

RSpec.describe Ituob::Registers::SnapshotWriter do
  let(:tmpdir) { Dir.mktmpdir('snapshot-writer-spec') }
  after { FileUtils.rm_rf(tmpdir) }

  let(:writer) { described_class.new(output_root: tmpdir) }

  def build_state(at_ob_issue:, entries: {}, lapsed: [], deleted: [], history: [])
    Ituob::Registers::State.new(
      register_id: 'TEST',
      at_ob_issue: at_ob_issue,
      entries: entries,
      lapsed_keys: lapsed,
      deleted_keys: deleted,
      history: history,
    )
  end

  let(:manifest_fields) do
    {
      register_id: 'TEST',
      recommendation: 'X.999',
      title: { 'en' => 'Test register' },
      key_field: 'code',
      seed_issue: 1000,
    }
  end

  describe '#write' do
    it 'writes current.json, manifest.json, and one at-{N}.json per state' do
      current = build_state(at_ob_issue: nil, entries: { 'A' => {} })
      at_1000 = build_state(at_ob_issue: 1000, entries: { 'A' => {} })
      at_1100 = build_state(at_ob_issue: 1100, entries: { 'A' => {}, 'B' => {} })

      written = writer.write(
        slug: 'test',
        manifest_fields: manifest_fields,
        current_state: current,
        states_by_issue: { 1000 => at_1000, 1100 => at_1100 },
      )

      expect(written).to eq(4) # current + 2 at-N + manifest
      expect(File.file?(File.join(tmpdir, 'test', 'current.json'))).to be(true)
      expect(File.file?(File.join(tmpdir, 'test', 'at-1000.json'))).to be(true)
      expect(File.file?(File.join(tmpdir, 'test', 'at-1100.json'))).to be(true)
      expect(File.file?(File.join(tmpdir, 'test', 'manifest.json'))).to be(true)
    end

    it 'current.json contains the snapshot shape with the slug' do
      current = build_state(at_ob_issue: nil, entries: {
                               'A' => { 'code' => 'A', 'v' => 1 },
                             })
      writer.write(
        slug: 'test',
        manifest_fields: manifest_fields,
        current_state: current,
        states_by_issue: {},
      )

      parsed = JSON.parse(File.read(File.join(tmpdir, 'test', 'current.json')))
      expect(parsed['slug']).to eq('test')
      expect(parsed['entry_count']).to eq(1)
      expect(parsed['active_entries'].first['code']).to eq('A')
    end

    it 'manifest.json contains the catalog-derived fields and sorted touched issues' do
      current = build_state(at_ob_issue: nil)
      writer.write(
        slug: 'test',
        manifest_fields: manifest_fields,
        current_state: current,
        states_by_issue: { 1100 => build_state(at_ob_issue: 1100),
                           1000 => build_state(at_ob_issue: 1000) },
      )

      parsed = JSON.parse(File.read(File.join(tmpdir, 'test', 'manifest.json')))
      expect(parsed['register_id']).to eq('TEST')
      expect(parsed['recommendation']).to eq('X.999')
      expect(parsed['key_field']).to eq('code')
      expect(parsed['seed_issue']).to eq(1000)
      expect(parsed['touched_issues']).to eq([1000, 1100])
    end

    it 'skips nil-key entries in states_by_issue (e.g. for current-only registers)' do
      current = build_state(at_ob_issue: nil)
      writer.write(
        slug: 'test',
        manifest_fields: manifest_fields,
        current_state: current,
        states_by_issue: { nil => current, 1000 => build_state(at_ob_issue: 1000) },
      )

      # only at-1000 should be written, not at-nil
      expect(File.file?(File.join(tmpdir, 'test', 'at-1000.json'))).to be(true)
      Dir.children(File.join(tmpdir, 'test')).each do |f|
        expect(f).not_to include('at-.json')
      end
    end

    it 'creates the slug directory if it does not exist' do
      expect(Dir.exist?(File.join(tmpdir, 'new-slug'))).to be(false)
      writer.write(
        slug: 'new-slug',
        manifest_fields: manifest_fields,
        current_state: build_state(at_ob_issue: nil),
        states_by_issue: {},
      )
      expect(Dir.exist?(File.join(tmpdir, 'new-slug'))).to be(true)
    end
  end
end

RSpec.describe Ituob::Registers::State, '#to_snapshot' do
  def change(type:, code:, ob_issue_no:)
    Ituob::Registers::Change.new(
      type: type, register_id: 'TEST',
      identifier: { 'code' => code },
      ob_issue_no: ob_issue_no,
    )
  end

  it 'returns the JSON-ready wire format' do
    state = Ituob::Registers::State.new(
      register_id: 'TEST',
      at_ob_issue: 1100,
      entries: { 'A' => { 'code' => 'A', 'v' => 1 } },
      lapsed_keys: ['B'],
      deleted_keys: ['C'],
      history: [change(type: 'ADD', code: 'A', ob_issue_no: 1000)],
      error_count: 0,
    )

    snap = state.to_snapshot(slug: 'test')
    expect(snap).to eq({
      'slug' => 'test',
      'at_ob_issue' => 1100,
      'entry_count' => 1,
      'lapsed_count' => 1,
      'deleted_count' => 1,
      'error_count' => 0,
      'errors' => [],
      'active_entries' => [{ 'code' => 'A', 'v' => 1 }],
      'lapsed_keys' => ['B'],
      'lapse_reasons' => {},
      'deleted_keys' => ['C'],
      'history' => [
        { 'type' => 'ADD', 'ob_issue' => 1000, 'identifier' => { 'code' => 'A' } },
      ],
    })
  end

  it 'is pure — does not touch the filesystem' do
    state = Ituob::Registers::State.new(
      register_id: 'TEST', at_ob_issue: nil,
      entries: {}, lapsed_keys: [], deleted_keys: [], history: [],
    )
    expect { state.to_snapshot(slug: 'test') }.not_to raise_error
    expect(state.to_snapshot(slug: 'test')).to be_a(Hash)
  end
end
