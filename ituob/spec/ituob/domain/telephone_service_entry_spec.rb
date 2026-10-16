# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Domain::TelephoneServiceEntry do
  let(:message_hash) do
    {
      'type' => 'nnp',
      'country_name' => { 'en' => 'Gambia' },
      'phone_code' => '220',
      'contact' => { 'en' => "Mr Nicholas Jatta\nDeputy Director" },
      'communications' => [
        {
          'date' => '2012-02-06',
          'contents' => {
            'en' => {
              'type' => 'doc',
              'content' => [
                { 'type' => 'paragraph',
                  'content' => [{ 'type' => 'text', 'text' => 'Updated NNP for Gambia.' }] },
              ],
            },
          },
        },
      ],
    }
  end

  describe '.from_message_hash' do
    it 'builds a country with name, phone, contact' do
      entry = described_class.from_message_hash(message_hash)
      expect(entry.country.en_name).to eq('Gambia')
      expect(entry.country.phone_code).to eq('220')
      expect(entry.country.contact_text).to include('Mr Nicholas Jatta')
    end

    it 'builds a list of communications' do
      entry = described_class.from_message_hash(message_hash)
      expect(entry.communications.length).to eq(1)
      expect(entry.communications.first.date).to eq('2012-02-06')
      expect(entry.communications.first.body_text).to include('Updated NNP')
    end

    it 'handles missing communications' do
      hash = message_hash.reject { |k, _| k == 'communications' }
      entry = described_class.from_message_hash(hash)
      expect(entry.communications).to be_empty
    end
  end
end

RSpec.describe Ituob::Domain::TelephoneServiceCommunication do
  it 'is frozen on construction' do
    comm = described_class.new(date: '2020-01-01', contents: nil)
    expect(comm).to be_frozen
  end

  describe '#body_text' do
    it 'walks the contents doc for text nodes' do
      contents = { 'type' => 'doc', 'content' => [
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Hello' }] },
      ] }
      comm = described_class.new(date: nil, contents: contents)
      expect(comm.body_text).to eq('Hello')
    end

    it 'returns empty string for nil contents' do
      expect(described_class.new(date: nil, contents: nil).body_text).to eq('')
    end
  end
end

RSpec.describe Ituob::Domain::TelephoneServiceCountry do
  it 'extracts the English name from a localized hash' do
    country = described_class.new(name: { 'en' => 'Gambia', 'fr' => 'Gambie' })
    expect(country.en_name).to eq('Gambia')
  end

  it 'falls back to a plain string name' do
    country = described_class.new(name: 'Gambia')
    expect(country.en_name).to eq('Gambia')
  end

  it 'extracts contact text from a localized hash' do
    country = described_class.new(name: nil, contact: { 'en' => 'Mr X' })
    expect(country.contact_text).to eq('Mr X')
  end
end
