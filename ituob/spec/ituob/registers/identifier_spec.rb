# frozen_string_literal: true

require 'spec_helper'
require 'ituob/registers'

RSpec.describe Ituob::Registers::Identifier do
  describe 'direct (by code)' do
    subject(:id) { described_class.new(code: 'ABC') }

    it 'is direct' do
      expect(id).to be_direct
    end

    it 'matches when entry key matches' do
      expect(id.matches?({ 'code' => 'ABC' }, 'code')).to be true
      expect(id.matches?({ 'code' => 'DEF' }, 'code')).to be false
      expect(id.matches?(nil, 'code')).to be false
    end

    it 'serializes to hash' do
      expect(id.to_hash).to eq({ 'code' => 'ABC' })
    end
  end

  describe 'query (by field/value)' do
    subject(:id) do
      described_class.new(query: { 'field' => 'country_or_area', 'value' => 'France' })
    end

    it 'is not direct' do
      expect(id).not_to be_direct
    end

    it 'matches on equals operator' do
      expect(id.matches?({ 'country_or_area' => 'France' }, 'code')).to be true
      expect(id.matches?({ 'country_or_area' => 'Germany' }, 'code')).to be false
    end

    it 'serializes to hash' do
      expect(id.to_hash).to eq({
        'query' => {
          'field' => 'country_or_area',
          'value' => 'France',
          'operator' => 'equals',
        },
      })
    end
  end

  describe 'operators' do
    it 'supports contains' do
      id = described_class.new(query: { 'field' => 'name', 'value' => 'Telecom', 'operator' => 'contains' })
      expect(id.matches?({ 'name' => 'France Telecom' }, 'code')).to be true
      expect(id.matches?({ 'name' => 'Orange' }, 'code')).to be false
    end

    it 'supports startsWith' do
      id = described_class.new(query: { 'field' => 'code', 'value' => 'ABC', 'operator' => 'startsWith' })
      expect(id.matches?({ 'code' => 'ABCDE' }, 'code')).to be true
      expect(id.matches?({ 'code' => 'XYZAB' }, 'code')).to be false
      expect(id.matches?({ 'code' => 'XABC' }, 'code')).to be false
    end

    it 'supports endsWith' do
      id = described_class.new(query: { 'field' => 'code', 'value' => 'XYZ', 'operator' => 'endsWith' })
      expect(id.matches?({ 'code' => 'ABCXYZ' }, 'code')).to be true
      expect(id.matches?({ 'code' => 'XYZAB' }, 'code')).to be false
      expect(id.matches?({ 'code' => 'ABXYCD' }, 'code')).to be false
    end

    it 'supports greaterThan (lexicographic string comparison)' do
      id = described_class.new(query: { 'field' => 'code', 'value' => 'M', 'operator' => 'greaterThan' })
      expect(id.matches?({ 'code' => 'N' }, 'code')).to be true
      expect(id.matches?({ 'code' => 'Z' }, 'code')).to be true
      expect(id.matches?({ 'code' => 'A' }, 'code')).to be false
      expect(id.matches?({ 'code' => 'M' }, 'code')).to be false # equal is not greater
    end

    it 'supports lessThan (lexicographic string comparison)' do
      id = described_class.new(query: { 'field' => 'code', 'value' => 'M', 'operator' => 'lessThan' })
      expect(id.matches?({ 'code' => 'A' }, 'code')).to be true
      expect(id.matches?({ 'code' => 'L' }, 'code')).to be true
      expect(id.matches?({ 'code' => 'Z' }, 'code')).to be false
      expect(id.matches?({ 'code' => 'M' }, 'code')).to be false # equal is not less
    end

    it 'supports in' do
      id = described_class.new(query: { 'field' => 'code', 'value' => %w[ABC DEF], 'operator' => 'in' })
      expect(id.matches?({ 'code' => 'ABC' }, 'code')).to be true
      expect(id.matches?({ 'code' => 'XYZ' }, 'code')).to be false
    end

    it 'rejects unknown operators' do
      expect {
        described_class.new(query: { 'field' => 'x', 'value' => 1, 'operator' => 'frobnicate' })
      }.to raise_error(ArgumentError)
    end
  end

  describe '.from_hash' do
    it 'builds a direct identifier' do
      expect(described_class.from_hash('code' => 'ABC')).to be_direct
    end

    it 'builds a query identifier' do
      built = described_class.from_hash('query' => { 'field' => 'f', 'value' => 'v' })
      expect(built).not_to be_direct
    end
  end

  it 'requires exactly one of code or query' do
    expect { described_class.from_hash({}) }.to raise_error(ArgumentError)
    expect { described_class.new(code: 'A', query: { 'field' => 'f', 'value' => 'v' }) }
      .to raise_error(ArgumentError)
  end

  it 'is frozen' do
    expect(described_class.new(code: 'ABC')).to be_frozen
  end
end
