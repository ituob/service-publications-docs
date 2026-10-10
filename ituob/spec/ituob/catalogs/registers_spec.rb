# frozen_string_literal: true

require 'spec_helper'
require 'ituob/catalogs'

RSpec.describe Ituob::Catalogs::Registers do
  before { described_class.reset! }

  describe '.all_register_ids' do
    it 'lists known registers' do
      ids = described_class.all_register_ids
      expect(ids).to include('E118_IIN', 'E212_MNC', 'M1400_ICC', 'F1')
    end
  end

  describe '.find' do
    it 'returns the entry by register_id' do
      entry = described_class.find('E212_MNC')
      expect(entry.title_en).to include('Mobile Network Codes')
      expect(entry.recommendation).to eq('E.212')
      expect(entry.key_field).to eq('mcc_mnc_codes')
    end
  end

  describe '.find_by_slug' do
    it 'returns the entry by filesystem slug' do
      entry = described_class.find_by_slug('e212-mnc')
      expect(entry.register_id).to eq('E212_MNC')
    end
  end

  describe '.for_recommendation' do
    it 'returns every register created by a recommendation' do
      expect(described_class.for_recommendation('E.212').map(&:register_id).sort)
        .to eq(%w[E212_ICC E212_MNC])
    end

    it 'is empty for unknown recommendations' do
      expect(described_class.for_recommendation('Z.999')).to be_empty
    end
  end

  describe '.slug_for' do
    it 'returns the catalogued slug for known IDs' do
      expect(described_class.slug_for('E212_MNC')).to eq('e212-mnc')
    end

    it 'derives a slug for unknown IDs' do
      expect(described_class.slug_for('Z999_New_Thing')).to eq('z999-new-thing')
    end
  end
end

RSpec.describe Ituob::Catalogs::Recommendations do
  before { described_class.reset! }

  describe '.all' do
    it 'lists known recommendations' do
      codes = described_class.all.map(&:code)
      expect(codes).to include('E.212', 'E.164', 'M.1400', 'F.1')
    end
  end

  describe '.find' do
    it 'returns the entry by code' do
      entry = described_class.find('E.212')
      expect(entry.title_en).to include('international identification plan')
      expect(entry.bureau).to eq('ITU-T')
    end
  end
end
