# frozen_string_literal: true

require 'spec_helper'
require 'ituob/registers'

RSpec.describe Ituob::Registers::InlineChangeSource do
  let(:register_id) { 'TEST' }

  def change(type:, code:, ob_issue_no:)
    Ituob::Registers::Change.new(
      type: type, register_id: register_id,
      identifier: { 'code' => code },
      ob_issue_no: ob_issue_no,
    )
  end

  describe '#each_sorted' do
    it 'yields changes in canonical (sorted) order regardless of input order' do
      a = change(type: 'ADD', code: 'A', ob_issue_no: 1100)
      b = change(type: 'ADD', code: 'B', ob_issue_no: 1000)
      source = described_class.new(register_id: register_id, changes: [a, b])

      yielded = []
      source.each_sorted { |c| yielded << c }
      expect(yielded.map(&:ob_issue_no)).to eq([1000, 1100])
    end

    it 'returns an Enumerator when called without a block' do
      source = described_class.new(register_id: register_id, changes: [])
      expect(source.each_sorted).to be_an(Enumerator)
    end

    it 'yields nothing for an empty source' do
      source = described_class.new(register_id: register_id, changes: [])
      expect { |b| source.each_sorted(&b) }.not_to yield_control
    end
  end

  describe '#seed_issue' do
    it 'returns the ob_issue_no of the first SEED change' do
      seed = change(type: 'SEED', code: '__seed__', ob_issue_no: 900)
      add  = change(type: 'ADD',  code: 'A',           ob_issue_no: 1000)
      source = described_class.new(register_id: register_id, changes: [add, seed])
      expect(source.seed_issue).to eq(900)
    end

    it 'returns nil when there is no SEED change' do
      add = change(type: 'ADD', code: 'A', ob_issue_no: 1000)
      source = described_class.new(register_id: register_id, changes: [add])
      expect(source.seed_issue).to be_nil
    end
  end

  describe 'ChangeSource contract' do
    it 'is a ChangeSource subclass' do
      expect(described_class.ancestors).to include(Ituob::Registers::ChangeSource)
    end

    it 'exposes register_id from the superclass' do
      source = described_class.new(register_id: 'F1', changes: [])
      expect(source.register_id).to eq('F1')
    end

    it 'supports each_until via the inherited each_sorted contract' do
      a = change(type: 'ADD', code: 'A', ob_issue_no: 1000)
      b = change(type: 'ADD', code: 'B', ob_issue_no: 1100)
      c = change(type: 'ADD', code: 'C', ob_issue_no: 1200)
      source = described_class.new(register_id: register_id, changes: [a, b, c])

      yielded = []
      source.each_until(1100) { |ch| yielded << ch }
      expect(yielded.map(&:ob_issue_no)).to eq([1000, 1100])
    end
  end

  describe 'integration with Replay' do
    it 'produces correct state via Replay#at_issue' do
      seed = Ituob::Registers::Change.new(
        type: 'SEED', register_id: register_id,
        identifier: { 'code' => '__seed__' },
        data: [{ 'code' => 'A', 'v' => 1 }, { 'code' => 'B', 'v' => 2 }],
        ob_issue_no: 1000,
      )
      source = described_class.new(register_id: register_id, changes: [seed])
      replay = Ituob::Registers::Replay.new(
        register_id: register_id, key_field: 'code', source: source,
      )

      state = replay.at_issue(1000)
      expect(state.entry_count).to eq(2)
      expect(state.entries.keys).to eq(%w[A B])
    end
  end
end
