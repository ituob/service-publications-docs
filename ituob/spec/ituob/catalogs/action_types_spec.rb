# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Catalogs::ActionTypes do
  describe '.valid?' do
    it 'returns true for canonical action types' do
      %w[ADD SUP REP LIR MOD DEL].each do |t|
        expect(described_class.valid?(t)).to be(true)
      end
    end

    it 'accepts trailing asterisks (used for delayed-effective-date)' do
      expect(described_class.valid?('ADD*')).to be(true)
      expect(described_class.valid?('SUP**')).to be(true)
    end

    it 'returns false for non-canonical strings' do
      %w[INSERT REMOVE DELETE_BY HOW by: te) ***].each do |t|
        expect(described_class.valid?(t)).to be(false), "expected #{t.inspect} to be invalid"
      end
    end

    it 'returns false for non-strings' do
      expect(described_class.valid?(nil)).to be(false)
      expect(described_class.valid?(123)).to be(false)
    end
  end

  describe '.normalize' do
    it 'uppercases and strips trailing asterisks' do
      expect(described_class.normalize('add')).to eq('ADD')
      expect(described_class.normalize('Add*')).to eq('ADD')
      expect(described_class.normalize(' SUP ')).to eq('SUP')
    end

    it 'returns nil for non-canonical values' do
      expect(described_class.normalize('XYZ')).to be_nil
      expect(described_class.normalize(nil)).to be_nil
    end
  end

  describe '.find_last_in' do
    it 'finds the last action keyword in a string' do
      expect(described_class.find_last_in('Germany (Federal Republic of) ADD')).to eq('ADD')
      expect(described_class.find_last_in('P 16 and 17 Denmark SUP (delete)')).to eq('SUP')
    end

    it 'returns nil when no keyword is present' do
      expect(described_class.find_last_in('Nothing here')).to be_nil
      expect(described_class.find_last_in('')).to be_nil
      expect(described_class.find_last_in(nil)).to be_nil
    end
  end

  describe '.rep_equivalent?' do
    it 'returns true for REP and LIR' do
      expect(described_class.rep_equivalent?('REP')).to be(true)
      expect(described_class.rep_equivalent?('LIR')).to be(true)
      expect(described_class.rep_equivalent?('lir')).to be(true)
    end

    it 'returns false for other actions' do
      expect(described_class.rep_equivalent?('ADD')).to be(false)
      expect(described_class.rep_equivalent?('SUP')).to be(false)
    end
  end
end
