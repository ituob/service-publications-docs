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
