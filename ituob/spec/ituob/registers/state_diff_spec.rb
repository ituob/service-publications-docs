# frozen_string_literal: true

require 'spec_helper'
require 'ituob/registers'

RSpec.describe Ituob::Registers::StateDiff do
  let(:register_id) { 'TEST' }

  def state(at_ob_issue:, entries: {}, lapsed: [], deleted: [])
    Ituob::Registers::State.new(
      register_id: register_id,
      at_ob_issue: at_ob_issue,
      entries: entries,
      lapsed_keys: lapsed,
      deleted_keys: deleted,
      history: [],
    )
  end

  describe '.between' do
    it 'returns an empty diff when both states are identical' do
      from = state(at_ob_issue: 1000, entries: { 'A' => { 'v' => 1 } })
      to   = state(at_ob_issue: 1100, entries: { 'A' => { 'v' => 1 } })

      diff = described_class.between(from, to)
      expect(diff).to be_empty
      expect(diff.total_change_count).to eq(0)
    end

    it 'reports added keys' do
      from = state(at_ob_issue: 1000, entries: { 'A' => {} })
      to   = state(at_ob_issue: 1100, entries: { 'A' => {}, 'B' => {} })

      diff = described_class.between(from, to)
      expect(diff.added_keys).to eq(['B'])
      expect(diff.removed_keys).to be_empty
    end

    it 'reports removed keys' do
      from = state(at_ob_issue: 1000, entries: { 'A' => {}, 'B' => {} })
      to   = state(at_ob_issue: 1100, entries: { 'A' => {} })

      diff = described_class.between(from, to)
      expect(diff.removed_keys).to eq(['B'])
    end

    it 'reports modified keys when content differs' do
      from = state(at_ob_issue: 1000, entries: { 'A' => { 'v' => 1 } })
      to   = state(at_ob_issue: 1100, entries: { 'A' => { 'v' => 2 } })

      diff = described_class.between(from, to)
      expect(diff.modified_keys).to eq(['A'])
    end

    it 'reports lapsed keys when a previously-active key is marked lapsed' do
      from = state(at_ob_issue: 1000, entries: { 'A' => {} }, lapsed: [])
      to   = state(at_ob_issue: 1100, entries: { 'A' => {} }, lapsed: ['A'])

      diff = described_class.between(from, to)
      expect(diff.lapsed_keys).to eq(['A'])
    end

    it 'reports unlapsed keys when a previously-lapsed key is reactivated' do
      from = state(at_ob_issue: 1000, entries: { 'A' => {} }, lapsed: ['A'])
      to   = state(at_ob_issue: 1100, entries: { 'A' => {} }, lapsed: [])

      diff = described_class.between(from, to)
      expect(diff.unlapsed_keys).to eq(['A'])
    end

    it 'does not flag a key as unlapsed when it has been removed entirely' do
      from = state(at_ob_issue: 1000, entries: { 'A' => {} }, lapsed: ['A'])
      to   = state(at_ob_issue: 1100, entries: {}, lapsed: [])

      diff = described_class.between(from, to)
      expect(diff.unlapsed_keys).to be_empty
      expect(diff.removed_keys).to eq(['A'])
    end

    it 'sorts keys for deterministic output' do
      from = state(at_ob_issue: 1000, entries: {})
      to   = state(at_ob_issue: 1100, entries: { 'C' => {}, 'A' => {}, 'B' => {} })

      diff = described_class.between(from, to)
      expect(diff.added_keys).to eq(%w[A B C])
    end
  end

  describe 'immutability' do
    it 'freezes all key arrays on construction' do
      diff = described_class.from_hash(
        'from_issue' => 1000, 'to_issue' => 1100,
        'added_keys' => ['A'], 'removed_keys' => ['B'], 'modified_keys' => ['C'],
        'lapsed_keys' => ['D'], 'unlapsed_keys' => ['E'],
      )
      expect(diff).to be_frozen
      expect(diff.added_keys).to be_frozen
      expect(diff.removed_keys).to be_frozen
    end
  end

  describe '#to_hash' do
    it 'round-trips through a hash' do
      diff = described_class.from_hash(
        'from_issue' => 1000, 'to_issue' => 1100,
        'added_keys' => ['A'], 'removed_keys' => [], 'modified_keys' => ['B'],
        'lapsed_keys' => [], 'unlapsed_keys' => [],
      )
      h = diff.to_hash['state_diff'] || diff.to_hash
      # lutaml-model may wrap output under the class name key; tolerate either.
      h = h.first[1] if h.is_a?(Hash) && h.key?('state_diff')
      expect(h['from_issue']).to eq(1000).or eq(1000)
      expect(h['to_issue']).to eq(1100)
      expect(h['added_keys']).to include('A')
      expect(h['modified_keys']).to include('B')
    end
  end
end

RSpec.describe Ituob::Registers::Replay, '#diff' do
  let(:source) do
    # InlineChangeSource replaces the previous anonymous Class.new.
    Ituob::Registers::InlineChangeSource.new(
      register_id: 'TEST',
      changes: [
        Ituob::Registers::Change.new(
          type: 'ADD', register_id: 'TEST',
          identifier: { 'code' => 'A' },
          data: { 'v' => 1 }, ob_issue_no: 1000,
        ),
        Ituob::Registers::Change.new(
          type: 'ADD', register_id: 'TEST',
          identifier: { 'code' => 'B' },
          data: { 'v' => 2 }, ob_issue_no: 1100,
        ),
        Ituob::Registers::Change.new(
          type: 'MOD', register_id: 'TEST',
          identifier: { 'code' => 'A' },
          data: { 'v' => 9 }, ob_issue_no: 1200,
        ),
      ],
    )
  end

  let(:replay) do
    described_class.new(register_id: 'TEST', key_field: 'code', source: source)
  end

  it 'returns a StateDiff between two issues' do
    diff = replay.diff(1000, 1200)
    expect(diff).to be_a(Ituob::Registers::StateDiff)
    expect(diff.added_keys).to eq(['B'])
    expect(diff.modified_keys).to eq(['A'])
  end

  it 'raises ArgumentError when from_issue is nil' do
    expect { replay.diff(nil, 1100) }.to raise_error(ArgumentError)
  end

  it 'raises ArgumentError when to_issue is nil' do
    expect { replay.diff(1000, nil) }.to raise_error(ArgumentError)
  end
end
