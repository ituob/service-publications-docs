# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'

RSpec.describe Ituob::Models::OldIssue do
  describe 'AMENDMENT_TYPE_TO_CLASS' do
    it 'maps every publication ID to a model class' do
      registry = described_class::AMENDMENT_TYPE_TO_CLASS
      expect(registry).not_to be_empty
      registry.each do |pub_id, klass|
        expect(klass).to be_a(Class), "#{pub_id} maps to #{klass.inspect}, expected a Class"
      end
    end

    it 'includes structured amendment types' do
      registry = described_class::AMENDMENT_TYPE_TO_CLASS
      %w[E118_IIN DP E164_ACN E164_CC F32_TDI E212_MNC E218_TRCC
         F400_ADMD M1400_ICC Q708_ISPC Q708_SANC T35_NA X121_DNIC].each do |pub_id|
        expect(registry).to have_key(pub_id), "Missing amendment type: #{pub_id}"
      end
    end

    it 'maps textual types to TextAmendment' do
      registry = described_class::AMENDMENT_TYPE_TO_CLASS
      # NNP is semantic since TODO.complete/50.
      %w[RR.25.1 BUREAUFAX].each do |pub_id|
        expect(registry[pub_id]).to be(Ituob::Models::TextAmendment)
      end
    end

    it 'has no duplicate class mappings for distinct publications' do
      mappings = described_class::AMENDMENT_TYPE_TO_CLASS
      structured = mappings.reject { |_, k| k == Ituob::Models::TextAmendment }
      # Each structured publication maps to a unique class
      classes = structured.values
      expect(classes.uniq.length).to eq(classes.length)
    end
  end

  describe 'GENERAL_TYPE_TO_CLASS' do
    it 'maps general message types to model classes' do
      registry = described_class::GENERAL_TYPE_TO_CLASS
      expect(registry).not_to be_empty
      registry.each do |type, klass|
        expect(klass).to be_a(Class), "#{type} maps to #{klass.inspect}, expected a Class"
      end
    end
  end
end
