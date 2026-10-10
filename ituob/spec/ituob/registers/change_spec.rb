# frozen_string_literal: true

require 'spec_helper'
require 'ituob/registers'

RSpec.describe Ituob::Registers::Change do
  describe '.from_hash' do
    subject(:change) do
      described_class.from_hash(
        'type' => 'ADD',
        'register' => 'F1',
        'identifier' => { 'code' => 'ABC' },
        'data' => { 'code' => 'ABC', 'field' => 'accounts' },
        'ob_issue_no' => '700',
        'reference' => 'OB-700',
      )
    end

    it 'coerces type to ActionType' do
      expect(change.action_type).to be_a(Ituob::Registers::ActionType)
      expect(change.type).to eq('ADD')
    end

    it 'coerces identifier to Identifier' do
      expect(change.identifier).to be_a(Ituob::Registers::Identifier)
      expect(change.identifier.code).to eq('ABC')
    end

    it 'coerces ob_issue_no to integer' do
      expect(change.ob_issue_no).to eq(700)
    end

    it 'preserves register_id, data, reference' do
      expect(change.register_id).to eq('F1')
      expect(change.data['code']).to eq('ABC')
      expect(change.reference).to eq('OB-700')
    end

    it 'freezes the data' do
      expect(change.data).to be_frozen
    end

    it 'is frozen itself' do
      expect(change).to be_frozen
    end
  end

  describe 'ordering' do
    it 'orders by ob_issue_no ascending' do
      earlier = described_class.new(
        type: 'ADD', register_id: 'F1',
        identifier: { 'code' => 'A' },
        ob_issue_no: 700,
      )
      later = described_class.new(
        type: 'ADD', register_id: 'F1',
        identifier: { 'code' => 'B' },
        ob_issue_no: 800,
      )
      expect([later, earlier].sort).to eq([earlier, later])
    end

    it 'uses identifier code as tiebreaker for same-issue changes' do
      a = described_class.new(type: 'ADD', register_id: 'F1',
                               identifier: { 'code' => 'B' }, ob_issue_no: 700)
      b = described_class.new(type: 'SUP', register_id: 'F1',
                               identifier: { 'code' => 'A' }, ob_issue_no: 700)
      expect([a, b].sort).to eq([b, a])
    end
  end

  describe 'predicates' do
    it 'distinguishes action types' do
      add = described_class.new(type: 'ADD', register_id: 'X', identifier: { 'code' => 'A' })
      sup = described_class.new(type: 'SUP', register_id: 'X', identifier: { 'code' => 'A' })
      seed = described_class.new(type: 'SEED', register_id: 'X', identifier: { 'code' => 'A' })
      expect(add).to be_add
      expect(sup).to be_sup
      expect(seed).to be_seed
    end
  end
end
