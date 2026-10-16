# frozen_string_literal: true

require 'spec_helper'
require 'set'
require 'ituob/registers'

RSpec.describe Ituob::Registers::State do
  let(:entries) { { 'ABC' => { 'code' => 'ABC', 'field' => 'accounts' },
                    'DEF' => { 'code' => 'DEF', 'field' => 'delivery' } } }
  let(:lapsed) { Set.new(['DEF']) }
  let(:deleted) { Set.new(['GHI']) }
  let(:history) { [] }

  let(:state) do
    described_class.new(
      register_id: 'F1', at_ob_issue: 700,
      entries: entries, lapsed_keys: lapsed, deleted_keys: deleted,
      history: history,
    )
  end

  describe '#active_entries' do
    it 'excludes lapsed keys' do
      expect(state.active_entries.keys).to eq(['ABC'])
    end

    it 'is memoised (same object returned)' do
      expect(state.active_entries).to be(state.active_entries)
    end
  end

  describe '#entry_for' do
    it 'returns the entry by key' do
      expect(state.entry_for('ABC')['field']).to eq('accounts')
    end

    it 'returns nil for unknown keys' do
      expect(state.entry_for('XYZ')).to be_nil
    end
  end

  describe '#has_key?' do
    it 'returns true for active entries' do
      expect(state.has_key?('ABC')).to be true
    end

    it 'returns false for lapsed entries' do
      expect(state.has_key?('DEF')).to be false
    end
  end

  describe '#lapsed?' do
    it 'returns true for lapsed keys' do
      expect(state.lapsed?('DEF')).to be true
    end

    it 'returns false for active keys' do
      expect(state.lapsed?('ABC')).to be false
    end
  end

  describe '#deleted?' do
    it 'returns true for deleted keys' do
      expect(state.deleted?('GHI')).to be true
    end
  end

  describe '#first_issue and #last_issue' do
    let(:history) do
      [
        Ituob::Registers::Change.new(type: 'SEED', register_id: 'F1',
                                      identifier: { 'code' => 'S' }, ob_issue_no: 669),
        Ituob::Registers::Change.new(type: 'ADD', register_id: 'F1',
                                      identifier: { 'code' => 'X' }, ob_issue_no: 700),
      ]
    end

    it 'returns first change issue' do
      expect(state.first_issue).to eq(669)
    end

    it 'returns last change issue' do
      expect(state.last_issue).to eq(700)
    end
  end

  describe '#to_h' do
    it 'includes all summary fields' do
      h = state.to_summary_hash
      expect(h[:register_id]).to eq('F1')
      expect(h[:at_ob_issue]).to eq(700)
      expect(h[:entry_count]).to eq(1)
      expect(h[:lapsed_count]).to eq(1)
      expect(h[:deleted_count]).to eq(1)
      expect(h[:error_count]).to eq(0)
    end
  end

  describe 'deep-freeze' do
    it 'is frozen' do
      expect(state).to be_frozen
    end

    it 'freezes entry values' do
      expect(state.entries['ABC']).to be_frozen
      expect {
        state.entries['ABC']['field'] = 'hacked'
      }.to raise_error(FrozenError)
    end
  end
end

RSpec.describe Ituob::Registers::StateBuilder do
  let(:builder) { described_class.new('F1') }

  describe '#set_entry and #entries' do
    it 'stores and retrieves entries' do
      builder.set_entry('ABC', { 'code' => 'ABC' })
      expect(builder.entries['ABC']).to eq({ 'code' => 'ABC' })
    end
  end

  describe '#remove_entry' do
    it 'deletes the entry' do
      builder.set_entry('ABC', {})
      builder.remove_entry('ABC')
      expect(builder.entries).not_to have_key('ABC')
    end
  end

  describe '#mark_lapsed and #clear_lapsed' do
    it 'tracks lapsed keys with reasons' do
      builder.set_entry('ABC', {})
      builder.mark_lapsed('ABC', reason: { 'en' => 'old' })
      expect(builder.lapsed_keys).to include('ABC')
      expect(builder.lapse_reasons['ABC']).to eq({ 'en' => 'old' })
    end

    it 'clears lapsed state' do
      builder.mark_lapsed('ABC')
      builder.clear_lapsed('ABC')
      expect(builder.lapsed_keys).not_to include('ABC')
    end
  end

  describe '#mark_deleted and #clear_deleted' do
    it 'tracks deleted keys' do
      builder.mark_deleted('ABC')
      expect(builder.deleted_keys).to include('ABC')
    end

    it 'clears deleted state' do
      builder.mark_deleted('ABC')
      builder.clear_deleted('ABC')
      expect(builder.deleted_keys).not_to include('ABC')
    end
  end

  describe '#record_history and #record_error' do
    it 'accumulates history' do
      c = Ituob::Registers::Change.new(type: 'ADD', register_id: 'F1',
                                        identifier: { 'code' => 'X' })
      builder.record_history(c)
      expect(builder.history).to eq([c])
    end

    it 'accumulates errors' do
      builder.record_error('something went wrong')
      expect(builder.errors).to eq(['something went wrong'])
    end
  end

  describe '#to_state' do
    it 'produces a frozen State with error_count' do
      builder.set_entry('ABC', {})
      builder.record_error('test error')
      state = builder.to_state(700)
      expect(state).to be_frozen
      expect(state.error_count).to eq(1)
      expect(state.entry_count).to eq(1)
    end
  end

  describe '#find_key_by_query' do
    it 'finds matching entry by query' do
      builder.set_entry('ABC', { 'field' => 'accounts' })
      id = Ituob::Registers::Identifier.new(
        query: { 'field' => 'field', 'value' => 'accounts' })
      expect(builder.find_key_by_query(id, 'code')).to eq('ABC')
    end
  end
end

RSpec.describe Ituob::Registers::State, 'error preservation' do
  it 'defaults to an empty errors array' do
    s = described_class.new(
      register_id: 'X', at_ob_issue: nil,
      entries: {}, lapsed_keys: [], deleted_keys: [], history: [],
    )
    expect(s.errors).to eq([])
    expect(s.errors).to be_frozen
  end

  it 'preserves errors passed at construction' do
    s = described_class.new(
      register_id: 'X', at_ob_issue: nil,
      entries: {}, lapsed_keys: [], deleted_keys: [], history: [],
      errors: ['bad change at OB 1234', 'LIR conflict: key "X"'],
    )
    expect(s.errors.length).to eq(2)
    expect(s.errors.first).to eq('bad change at OB 1234')
  end

  it 'includes errors in to_snapshot' do
    s = described_class.new(
      register_id: 'X', at_ob_issue: nil,
      entries: {}, lapsed_keys: [], deleted_keys: [], history: [],
      errors: ['boom'],
    )
    expect(s.to_snapshot(slug: 'x')['errors']).to eq(['boom'])
  end
end

RSpec.describe Ituob::Registers::State, 'lapse_reasons preservation' do
  it 'defaults to an empty hash' do
    s = described_class.new(
      register_id: 'X', at_ob_issue: nil,
      entries: {}, lapsed_keys: [], deleted_keys: [], history: [],
    )
    expect(s.lapse_reasons).to eq({})
    expect(s.lapse_reasons).to be_frozen
  end

  it 'preserves lapse_reasons passed at construction' do
    s = described_class.new(
      register_id: 'X', at_ob_issue: nil,
      entries: {}, lapsed_keys: Set.new(['A']), deleted_keys: [], history: [],
      lapse_reasons: { 'A' => { 'en' => 'expired' } },
    )
    expect(s.lapse_reason_for('A')).to eq({ 'en' => 'expired' })
    expect(s.lapse_reason_for('unknown')).to be_nil
  end

  it 'includes lapse_reasons in to_snapshot' do
    s = described_class.new(
      register_id: 'X', at_ob_issue: nil,
      entries: {}, lapsed_keys: Set.new(['A']), deleted_keys: [], history: [],
      lapse_reasons: { 'A' => { 'en' => 'expired' } },
    )
    expect(s.to_snapshot(slug: 'x')['lapse_reasons'])
      .to eq({ 'A' => { 'en' => 'expired' } })
  end
end

RSpec.describe Ituob::Registers::StateBuilder, 'reason + error round-trip' do
  let(:builder) { Ituob::Registers::StateBuilder.new('F1') }

  it 'to_state preserves lapse_reasons and errors' do
    builder.set_entry('A', {})
    builder.mark_lapsed('A', reason: { 'en' => 'inactive' })
    builder.record_error('replay warning')

    state = builder.to_state(1200)
    expect(state.lapse_reason_for('A')).to eq({ 'en' => 'inactive' })
    expect(state.errors).to eq(['replay warning'])
  end
end
