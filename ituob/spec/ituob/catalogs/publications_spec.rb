# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Catalogs::Publications do
  describe '.slug_for' do
    it 'returns the registered slug for known publications' do
      expect(described_class.slug_for('E118_IIN')).to eq('e118-iin')
      expect(described_class.slug_for('M1400_ICC')).to eq('m1400-icc')
      expect(described_class.slug_for('NNP')).to eq('nnp')
      expect(described_class.slug_for('R_SP_LM.V')).to eq('list-v')
      expect(described_class.slug_for('R_SP_LN.VIII')).to eq('list-viii')
    end

    it 'returns the slug for List of Coast Stations (long publication ID)' do
      expect(described_class.slug_for('List of Coast Stations and Special Service Stations'))
        .to eq('coast-stations')
    end

    it 'computes a default slug for unknown publications' do
      expect(described_class.slug_for('E999_NEW')).to eq('e999-new')
    end
  end

  describe '.publication_for' do
    it 'reverse-maps a slug to a publication ID' do
      expect(described_class.publication_for('e118-iin')).to eq('E118_IIN')
      expect(described_class.publication_for('m1400-icc')).to eq('M1400_ICC')
      expect(described_class.publication_for('nnp')).to eq('NNP')
    end

    it 'returns nil for unknown slugs' do
      expect(described_class.publication_for('unknown-slug')).to be_nil
    end
  end

  describe '.classify' do
    it 'classifies structured publications' do
      expect(described_class.classify('E118_IIN')).to be_structured
      expect(described_class.classify('M1400_ICC')).to be_structured
      expect(described_class.classify('Q708_ISPC')).to be_structured
    end

    it 'classifies textual publications' do
      expect(described_class.classify('NNP')).to be_textual
      expect(described_class.classify('R_SP_LM.V')).to be_textual
      expect(described_class.classify('RR.25.1')).to be_textual
      expect(described_class.classify('List of Coast Stations and Special Service Stations')).to be_textual
    end
  end

  describe '.known?' do
    it 'returns true for registered publications' do
      expect(described_class.known?('E118_IIN')).to be(true)
    end

    it 'returns false for unknown publications' do
      expect(described_class.known?('UNKNOWN_PUB')).to be(false)
    end
  end

  describe '.parser_class_for' do
    it 'resolves the parser class name for a registered publication' do
      klass = described_class.parser_class_for('E118_IIN')
      expect(klass).to eq(Ituob::Models::E118Amendment)
    end

    it 'returns nil for textual publications' do
      expect(described_class.parser_class_for('NNP')).to be_nil
    end
  end
end

RSpec.describe Ituob::Catalogs::Publications::Classification do
  it 'is comparable via struct semantics' do
    structured = Ituob::Catalogs::Publications::STRUCTURED
    textual = Ituob::Catalogs::Publications::TEXTUAL
    expect(structured).to be_structured
    expect(textual).to be_textual
    expect(structured).not_to eq(textual)
  end
end
