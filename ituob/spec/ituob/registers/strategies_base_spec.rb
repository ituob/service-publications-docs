# frozen_string_literal: true

require 'spec_helper'
require 'ituob/registers'

RSpec.describe Ituob::Registers::Strategies::Base do
  describe '.entry_key' do
    it 'ignores a fallback cell holding only NBSP' do
      row = { 'admd' => nil, 'alt' => " " }
      expect(described_class.entry_key(row, 'admd', ['alt'])).to be_nil
    end

    it 'ignores a fallback cell holding only spaces and uses the next fallback' do
      row = { 'admd' => nil, 'alt' => '  ', 'code' => 'DK400' }
      expect(described_class.entry_key(row, 'admd', %w[alt code])).to eq('DK400')
    end

    it 'keeps a blank primary cell as the key, as before fallbacks existed' do
      row = { 'admd' => " ", 'code' => 'DK400' }
      expect(described_class.entry_key(row, 'admd', ['code'])).to eq(" ")
    end

    it 'keeps a real key verbatim' do
      expect(described_class.entry_key({ 'admd' => 'ATT' }, 'admd')).to eq('ATT')
    end
  end

  describe '.call with a key repeated inside one change' do
    let(:builder) { Ituob::Registers::StateBuilder.new('F400_ADMD') }
    let(:change) do
      Ituob::Registers::Change.new(
        type: 'SUP', register_id: 'F400_ADMD', identifier: { 'code' => 'DK400' },
        data: { 'entries' => [{ 'admd_name' => 'DK400' }, { 'admd_name' => ' ' }, { 'admd_name' => ' ' }] },
      )
    end

    it 'reports no conflict for the repeat' do
      builder.set_entry('DK400', { 'admd_name' => 'DK400' })
      builder.set_entry(' ', { 'admd_name' => ' ' })
      conflicts = []
      Ituob::Registers::Strategies::Sup.call(builder, change, 'admd_name') { |e| conflicts << e }
      expect(conflicts).to be_empty
      expect(builder.entries).to be_empty
    end
  end
end
