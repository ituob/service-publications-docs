# frozen_string_literal: true

require 'spec_helper'
require 'ituob/registers'

RSpec.describe Ituob::Registers::StateBuilder do
  let(:register_id) { 'TEST' }
  let(:builder) { described_class.new(register_id) }

  describe '#set_entry / #remove_entry' do
    it 'stores entries keyed by string' do
      builder.set_entry('A', { 'code' => 'A' })
      expect(builder.entries).to include('A')
    end

    it 'coerces symbol keys to strings' do
      builder.set_entry(:A, { 'code' => 'A' })
      expect(builder.entries).to include('A')
    end

    it 'removes entries' do
      builder.set_entry('A', { 'code' => 'A' })
      builder.remove_entry('A')
      expect(builder.entries).not_to include('A')
    end
  end

  describe '#mark_lapsed / #clear_lapsed' do
    it 'adds the key to lapsed_keys with an optional reason' do
      builder.set_entry('A', {})
      builder.mark_lapsed('A', reason: { 'en' => 'expired' })
      expect(builder.lapsed_keys).to include('A')
      expect(builder.lapse_reasons['A']).to eq({ 'en' => 'expired' })
    end

    it 'clear_lapsed removes the key and its reason' do
      builder.set_entry('A', {})
      builder.mark_lapsed('A', reason: { 'en' => 'expired' })
      builder.clear_lapsed('A')
      expect(builder.lapsed_keys).not_to include('A')
      expect(builder.lapse_reasons).not_to include('A')
    end
  end

  describe '#mark_deleted / #clear_deleted' do
    it 'tracks hard-deleted keys' do
      builder.mark_deleted('X')
      expect(builder.deleted_keys).to include('X')
      builder.clear_deleted('X')
      expect(builder.deleted_keys).not_to include('X')
    end
  end

  describe '#record_supersession' do
    it 'stores a single mapping per old_key' do
      builder.record_supersession('OLD', 'NEW')
      expect(builder.supersessions['OLD']).to eq('NEW')
    end
  end

  describe '#record_history' do
    it 'appends changes in order' do
      c1 = Ituob::Registers::Change.new(
        type: 'ADD', register_id: register_id,
        identifier: { 'code' => 'A' }, ob_issue_no: 1000,
      )
      c2 = Ituob::Registers::Change.new(
        type: 'MOD', register_id: register_id,
        identifier: { 'code' => 'A' }, ob_issue_no: 1100,
      )
      builder.record_history(c1)
      builder.record_history(c2)
      expect(builder.history).to eq([c1, c2])
    end
  end

  describe '#record_error' do
    it 'accumulates error messages' do
      builder.record_error('oops 1')
      builder.record_error('oops 2')
      expect(builder.errors).to eq(['oops 1', 'oops 2'])
    end
  end

  describe '#key_history' do
    let(:change) do
      Ituob::Registers::Change.new(
        type: type, register_id: register_id,
        identifier: { 'code' => '1170-001' }, ob_issue_no: 1170,
        data: { 'entries' => [{ 'code' => 'A' }, { 'code' => 'B' }] },
      )
    end
    let(:type) { 'REP' }

    before do
      builder.set_entry('A', { 'code' => 'A', 'name' => 'Alpha' })
      builder.set_entry('B', { 'code' => 'B', 'name' => 'Beta' })
      builder.set_entry('C', { 'code' => 'C', 'name' => 'Gamma' })
    end

    %w[ADD MOD LIR REP SUP DEL].each do |action|
      context "with a multi-row #{action}" do
        let(:type) { action }

        it 'records the change once under each affected data key' do
          builder.record_history(change)
          Ituob::Registers::Strategies::Resolver.apply(builder, change, 'code')

          expect(builder.key_history).to eq({ 'A' => [change], 'B' => [change] })
          expect(builder.history).to eq([change])
        end
      end
    end

    it 'records a lapse under the normalized key' do
      builder.record_history(change)
      builder.mark_lapsed(:A, reason: { 'en' => 'expired' })
      builder.mark_lapsed('A')

      expect(builder.key_history).to eq({ 'A' => [change] })
    end

    it 'records the resolved key for a query-based change' do
      queried = Ituob::Registers::Change.new(
        type: 'MOD', register_id: register_id,
        identifier: { 'query' => { 'field' => 'name', 'value' => 'Beta' } },
        data: { 'name' => 'Updated' }, ob_issue_no: 1170,
      )
      builder.record_history(queried)
      Ituob::Registers::Strategies::Resolver.apply(builder, queried, 'code')

      expect(builder.key_history).to eq({ 'B' => [queried] })
    end

    it 'keeps rejected changes only in the flat history' do
      rejected = Ituob::Registers::Change.new(
        type: 'SUP', register_id: register_id,
        identifier: { 'code' => '1171-001' }, ob_issue_no: 1171,
        data: { 'entries' => [{ 'code' => 'A' }, { 'code' => 'missing' }] },
      )
      builder.record_history(change)
      Ituob::Registers::Strategies::Resolver.apply(builder, change, 'code')
      builder.record_history(rejected)

      expect {
        Ituob::Registers::Strategies::Resolver.apply(builder, rejected, 'code')
      }.to raise_error(Ituob::Registers::Strategies::StrategyError)
      expect(builder.key_history).to eq({ 'A' => [change], 'B' => [change] })
      expect(builder.history).to eq([change, rejected])
    end

    it 'preserves earlier snapshots while recording later changes' do
      builder.record_history(change)
      Ituob::Registers::Strategies::Resolver.apply(builder, change, 'code')
      state = builder.to_state(1170)
      later = Ituob::Registers::Change.new(
        type: 'DEL', register_id: register_id,
        identifier: { 'code' => 'A' }, ob_issue_no: 1171,
      )
      builder.record_history(later)
      Ituob::Registers::Strategies::Resolver.apply(builder, later, 'code')
      current = builder.to_state(1171)

      expect(state.key_history).to eq({ 'A' => [change], 'B' => [change] })
      expect(state.history).to eq([change])
      expect(current.key_history).to eq({ 'A' => [change, later], 'B' => [change] })
      expect(current.history).to eq([change, later])
    end

    it 'preserves key histories through replay issue boundaries' do
      deletion = Ituob::Registers::Change.new(
        type: 'SUP', register_id: register_id,
        identifier: { 'code' => '1171-001' }, ob_issue_no: 1171,
        data: change.data,
      )
      source = Ituob::Registers::InlineChangeSource.new(
        register_id: register_id, changes: [change, deletion],
      )
      replay = Ituob::Registers::Replay.new(
        register_id: register_id, key_field: 'code', source: source,
      )
      states = replay.build_all_states

      expect(states[1170].key_history).to eq({ 'A' => [change], 'B' => [change] })
      expect(states[nil].key_history).to eq({
        'A' => [change, deletion], 'B' => [change, deletion],
      })
      expect(states[nil].history).to eq([change, deletion])
      expect(states[nil].entries).to be_empty
      expect(states[nil].errors).to be_empty
    end
  end

  describe '#find_key_by_query' do
    it 'returns the first key whose entry matches the identifier' do
      builder.set_entry('A', { 'code' => 'A', 'name' => 'Alpha' })
      builder.set_entry('B', { 'code' => 'B', 'name' => 'Beta' })

      query_id = Ituob::Registers::Identifier.new(
        query: { 'field' => 'name', 'value' => 'Beta', 'operator' => 'equals' },
      )
      expect(builder.find_key_by_query(query_id, 'code')).to eq('B')
    end

    it 'returns nil when nothing matches' do
      builder.set_entry('A', { 'code' => 'A' })
      query_id = Ituob::Registers::Identifier.new(
        query: { 'field' => 'code', 'value' => 'ZZZ', 'operator' => 'equals' },
      )
      expect(builder.find_key_by_query(query_id, 'code')).to be_nil
    end
  end

  describe '#to_state isolation' do
    # Regression guard: after TODO 43, mutating the builder must NOT
    # corrupt the State already emitted via #to_state. Pre-fix, this
    # would silently share row references between the builder's working
    # entries hash and the captured State's entries.
    it 'deep-freezes entries so subsequent builder mutation cannot leak' do
      builder.set_entry('A', { 'code' => 'A', 'v' => 1 })
      state = builder.to_state(1000)

      # Sanity: the snapshot sees the entry
      expect(state.entries['A']['v']).to eq(1)
      # The captured row must be frozen
      expect(state.entries['A']).to be_frozen

      # Now mutate the builder's working entry
      builder.set_entry('A', { 'code' => 'A', 'v' => 999 })
      expect(builder.entries['A']['v']).to eq(999)

      # The captured State must not see the change
      expect(state.entries['A']['v']).to eq(1)
    end

    it 'returns a frozen State' do
      builder.set_entry('A', {})
      state = builder.to_state(1000)
      expect(state).to be_frozen
    end

    it 'counts errors as error_count on the State' do
      builder.record_error('one')
      builder.record_error('two')
      state = builder.to_state(1000)
      expect(state.error_count).to eq(2)
    end
  end
end
