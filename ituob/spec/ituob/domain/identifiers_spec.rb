# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Domain::Identifiers::IssueId do
  describe '.new' do
    it 'accepts an integer' do
      expect(described_class.new(1163).to_i).to eq(1163)
    end

    it 'accepts a numeric string' do
      expect(described_class.new('1163').to_i).to eq(1163)
    end

    it 'accepts another IssueId' do
      original = described_class.new(1163)
      expect(described_class.new(original).to_i).to eq(1163)
    end

    it 'raises TypeError for non-numeric values' do
      expect { described_class.new(nil) }.to raise_error(TypeError)
      expect { described_class.new([]) }.to raise_error(TypeError)
    end

    it 'raises ArgumentError for non-positive integers' do
      expect { described_class.new(0) }.to raise_error(ArgumentError)
      expect { described_class.new(-1) }.to raise_error(ArgumentError)
    end
  end

  describe 'comparability' do
    it 'is sortable with other IssueIds' do
      ids = [described_class.new(1002), described_class.new(1000), described_class.new(1001)]
      expect(ids.sort.map(&:to_i)).to eq([1000, 1001, 1002])
    end

    it 'is hashable' do
      set = Set.new([described_class.new(1000), described_class.new(1000)])
      expect(set.size).to eq(1)
    end
  end
end

RSpec.describe Ituob::Domain::Identifiers::DatasetSlug do
  it 'rejects empty values' do
    expect { described_class.new('') }.to raise_error(ArgumentError)
  end

  it 'rejects paths with separators' do
    expect { described_class.new('foo/bar') }.to raise_error(ArgumentError)
  end

  it 'exposes value via to_s' do
    expect(described_class.new('e118-iin').to_s).to eq('e118-iin')
  end
end

RSpec.describe Ituob::Domain::Identifiers::PublicationId do
  describe '#slug' do
    it 'resolves via the catalog' do
      expect(described_class.new('E118_IIN').slug.to_s).to eq('e118-iin')
      expect(described_class.new('NNP').slug.to_s).to eq('nnp')
    end
  end

  describe '#textual? / #structured?' do
    it 'reflects the catalog classification' do
      expect(described_class.new('NNP')).to be_textual
      expect(described_class.new('E118_IIN')).to be_structured
      expect(described_class.new('NNP')).not_to be_structured
      expect(described_class.new('E118_IIN')).not_to be_textual
    end
  end
end
