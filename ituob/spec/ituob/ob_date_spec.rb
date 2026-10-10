# frozen_string_literal: true

require 'spec_helper'
require 'date'
require 'ituob/ob_date'

RSpec.describe Ituob::ObDate do
  describe '.format' do
    it 'renders Date in canonical OB form' do
      expect(described_class.format(Date.new(2016, 5, 15))).to eq('15.V.2016')
    end

    it 'renders ISO date strings' do
      expect(described_class.format('2016-05-15')).to eq('15.V.2016')
      expect(described_class.format('2010-09-01')).to eq('1.IX.2010')
      expect(described_class.format('2019-12-15')).to eq('15.XII.2019')
    end

    it 'renders Time as the equivalent date' do
      expect(described_class.format(Time.utc(2016, 5, 15, 12, 0, 0))).to eq('15.V.2016')
    end

    it 'returns nil for nil input' do
      expect(described_class.format(nil)).to be_nil
    end

    it 'covers all twelve Roman-numeral months' do
      months = (1..12).map { |m| described_class.format(Date.new(2024, m, 15)) }
      expect(months).to eq(%w[15.I.2024 15.II.2024 15.III.2024 15.IV.2024 15.V.2024
                              15.VI.2024 15.VII.2024 15.VIII.2024 15.IX.2024
                              15.X.2024 15.XI.2024 15.XII.2024])
    end
  end

  describe '.parse' do
    it 'parses a canonical OB date' do
      expect(described_class.parse('15.V.2016')).to eq(Date.new(2016, 5, 15))
      expect(described_class.parse('1.IX.2010')).to eq(Date.new(2010, 9, 1))
    end

    it 'returns nil for non-matching strings' do
      expect(described_class.parse('invalid')).to be_nil
      expect(described_class.parse('15 May 2016')).to be_nil
      expect(described_class.parse('')).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end
  end

  describe '.format_long' do
    it 'renders the spelled-out English form' do
      expect(described_class.format_long(Date.new(2016, 5, 15))).to eq('15 May 2016')
    end
  end

  describe 'round-trip' do
    it 'parse(format(d)) returns the same date' do
      d = Date.new(2010, 9, 1)
      expect(described_class.parse(described_class.format(d))).to eq(d)
    end
  end
end
