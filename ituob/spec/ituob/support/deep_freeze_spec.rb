# frozen_string_literal: true

require 'spec_helper'
require 'ituob/support'

RSpec.describe Ituob::Support::DeepFreeze do
  let(:mod) { described_class }

  describe '.deep_freeze' do
    it 'freezes a String' do
      s = mod.deep_freeze('hello')
      expect(s).to be_frozen
    end

    it 'returns nil for nil input' do
      expect(mod.deep_freeze(nil)).to be_nil
    end

    it 'freezes a Hash and all nested values' do
      h = mod.deep_freeze({ a: 1, b: { c: 'x' }, d: [1, 2] })
      expect(h).to be_frozen
      expect(h[:b]).to be_frozen
      expect(h[:d]).to be_frozen
    end

    it 'freezes Arrays and their elements' do
      arr = mod.deep_freeze([{ a: 1 }, 'x', [2, 3]])
      expect(arr).to be_frozen
      expect(arr[0]).to be_frozen
      expect(arr[2]).to be_frozen
    end

    it 'returns the same object passed in (so callers can chain)' do
      input = { a: 1 }
      result = mod.deep_freeze(input)
      expect(result).to equal(input)
    end

    it 'deep-freezes arbitrarily nested structures' do
      data = mod.deep_freeze({ a: [1, { b: { c: [2, 3] } }] })
      expect(data[:a][1][:b][:c]).to be_frozen
    end

    it 'is idempotent on already-frozen input' do
      input = 'frozen'.freeze
      expect { mod.deep_freeze(input) }.not_to raise_error
    end
  end
end
