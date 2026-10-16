# frozen_string_literal: true

require 'spec_helper'
require 'ituob/support'

RSpec.describe Ituob::Support::HashField do
  let(:mod) { described_class }

  describe '.lookup' do
    it 'returns the string-keyed value when both forms are present (string wins)' do
      hash = { 'name' => 'String form', name: 'Symbol form' }
      expect(mod.lookup(hash, 'name')).to eq('String form')
      expect(mod.lookup(hash, :name)).to eq('String form')
    end

    it 'falls back to the symbol key when no string key exists' do
      hash = { name: 'Symbol form' }
      expect(mod.lookup(hash, 'name')).to eq('Symbol form')
    end

    it 'returns nil when neither form is present' do
      expect(mod.lookup({ 'other' => 1 }, 'name')).to be_nil
    end

    it 'returns nil for non-hash input' do
      expect(mod.lookup(nil, 'name')).to be_nil
      expect(mod.lookup('not a hash', 'name')).to be_nil
    end

    it 'coerces integer keys to string' do
      expect(mod.lookup({ '42' => 'answer' }, 42)).to eq('answer')
    end
  end

  describe '.set' do
    it 'writes to the canonical string key' do
      hash = {}
      mod.set(hash, 'name', 'Alice')
      expect(hash).to eq({ 'name' => 'Alice' })
    end

    it 'coerces symbol keys to strings' do
      hash = {}
      mod.set(hash, :name, 'Alice')
      expect(hash).to eq({ 'name' => 'Alice' })
    end

    it 'overwrites existing symbol-keyed value with the canonical string form' do
      hash = { name: 'old' }
      mod.set(hash, :name, 'new')
      expect(hash).to eq({ name: 'old', 'name' => 'new' })
    end
  end

  describe '.contains?' do
    it 'returns true for a string key' do
      expect(mod.contains?({ 'name' => 1 }, 'name')).to be(true)
    end

    it 'returns true for a symbol key' do
      expect(mod.contains?({ name: 1 }, 'name')).to be(true)
    end

    it 'returns false when neither form is present' do
      expect(mod.contains?({ other: 1 }, 'name')).to be(false)
    end

    it 'returns false for non-hash input' do
      expect(mod.contains?(nil, 'name')).to be(false)
    end
  end
end
