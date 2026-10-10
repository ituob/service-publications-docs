# frozen_string_literal: true

require 'spec_helper'
require 'ituob/registers'

RSpec.describe Ituob::Registers::ActionType do
  describe '.new' do
    it 'accepts valid action types' do
      %w[ADD SUP REP LIR MOD DEL SEED].each do |t|
        expect(described_class.new(t).value).to eq(t)
      end
    end

    it 'normalises lowercase to uppercase' do
      expect(described_class.new('add').value).to eq('ADD')
    end

    it 'rejects unknown types' do
      expect { described_class.new('XYZ') }.to raise_error(ArgumentError)
    end
  end

  describe '.coerce' do
    it 'returns the same object when given an ActionType' do
      at = described_class.new('ADD')
      expect(described_class.coerce(at)).to be(at)
    end

    it 'wraps a string' do
      expect(described_class.coerce('add').value).to eq('ADD')
    end
  end

  describe '#strategy_class_name' do
    it 'maps each action type to its strategy class' do
      expect(described_class.new('ADD').strategy_class_name)
        .to eq('Ituob::Registers::Strategies::Add')
      expect(described_class.new('SUP').strategy_class_name)
        .to eq('Ituob::Registers::Strategies::Sup')
      expect(described_class.new('REP').strategy_class_name)
        .to eq('Ituob::Registers::Strategies::Rep')
      expect(described_class.new('LIR').strategy_class_name)
        .to eq('Ituob::Registers::Strategies::Lir')
      expect(described_class.new('MOD').strategy_class_name)
        .to eq('Ituob::Registers::Strategies::Mod')
      expect(described_class.new('DEL').strategy_class_name)
        .to eq('Ituob::Registers::Strategies::Del')
      expect(described_class.new('SEED').strategy_class_name)
        .to eq('Ituob::Registers::Strategies::Seed')
    end
  end

  describe 'predicates' do
    it 'distinguishes destructive from non-destructive' do
      expect(described_class.new('SUP')).to be_destructive
      expect(described_class.new('LIR')).to be_destructive
      expect(described_class.new('DEL')).to be_destructive
      expect(described_class.new('ADD')).not_to be_destructive
      expect(described_class.new('SEED')).not_to be_destructive
    end

    it 'auto-generates a predicate for every VALID_TYPE' do
      # Convention: VALID_TYPES entry 'ADD' → method `add?` returning
      # true only when value == 'ADD'.
      described_class::VALID_TYPES.each do |type|
        predicate = "#{type.downcase}?"
        instance = described_class.new(type)
        expect(instance.public_send(predicate)).to be(true)
      end
    end

    it 'a predicate returns false for non-matching action types' do
      add = described_class.new('ADD')
      expect(add).to be_add
      expect(add).not_to be_sup
      expect(add).not_to be_seed
    end
  end

  it 'is frozen' do
    expect(described_class.new('ADD')).to be_frozen
  end
end
