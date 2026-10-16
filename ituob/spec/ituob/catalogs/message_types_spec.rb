# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Catalogs::MessageTypes do
  describe '.category' do
    it 'classifies structured types' do
      expect(described_class.category('running_annexes')).to be(:structured)
      expect(described_class.category('approved_recommendations')).to be(:structured)
    end

    it 'classifies textual types' do
      %w[sanc iptn ipns mid org_changes misc_communications
         service_restrictions custom callback_procedures
         telephone_service telephone_service_2 no_type].each do |t|
        expect(described_class.category(t)).to be(:textual), "expected #{t} to be textual"
      end
    end

    it 'returns nil for unknown types' do
      expect(described_class.category('unknown_type')).to be_nil
      expect(described_class.category('foo')).to be_nil
    end
  end

  describe '.known?' do
    it 'returns true for all declared types' do
      expect(described_class.known?('running_annexes')).to be(true)
      expect(described_class.known?('sanc')).to be(true)
    end

    it 'returns false for unknown types' do
      expect(described_class.known?('unknown')).to be(false)
    end
  end

  describe '.relative_path_for' do
    it 'routes structured types to general/' do
      expect(described_class.relative_path_for('running_annexes'))
        .to eq('general/running_annexes.yaml')
    end

    it 'routes textual types to per-type dirs' do
      expect(described_class.relative_path_for('sanc', sequence: 1))
        .to eq('sanc/001.yaml')
      expect(described_class.relative_path_for('iptn', sequence: 12))
        .to eq('iptn/012.yaml')
    end
  end
end
