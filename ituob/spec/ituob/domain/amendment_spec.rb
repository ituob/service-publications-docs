# frozen_string_literal: true

require 'spec_helper'
require 'ituob/domain'

RSpec.describe Ituob::Domain::Amendment do
  let(:publication_id) { Ituob::Domain::Identifiers::PublicationId.new('E.118') }
  let(:contents) { { 'en' => { 'type' => 'doc', 'content' => [] } } }

  describe '#initialize' do
    it 'coerces string publication_id to PublicationId' do
      amendment = described_class.new(publication_id: 'E.118', contents: contents)
      expect(amendment.publication_id).to be_a(Ituob::Domain::Identifiers::PublicationId)
    end

    it 'accepts a PublicationId directly' do
      amendment = described_class.new(publication_id: publication_id, contents: contents)
      expect(amendment.publication_id).to eq(publication_id)
    end

    it 'stores position_on when provided' do
      amendment = described_class.new(publication_id: 'E.118', position_on: '2024-01-01', contents: contents)
      expect(amendment.position_on).to eq('2024-01-01')
    end

    it 'captures extra keyword args' do
      amendment = described_class.new(publication_id: 'E.118', contents: contents, note: 'test')
      expect(amendment.extra[:note]).to eq('test')
    end
  end

  describe '#empty_contents?' do
    it 'returns true for nil contents' do
      amendment = described_class.new(publication_id: 'E.118', contents: nil)
      expect(amendment).to be_empty_contents
    end

    it 'returns true for empty hash' do
      amendment = described_class.new(publication_id: 'E.118', contents: {})
      expect(amendment).to be_empty_contents
    end

    it 'returns false for non-empty contents' do
      amendment = described_class.new(publication_id: 'E.118', contents: contents)
      expect(amendment).not_to be_empty_contents
    end
  end

  describe '#contents_en' do
    it 'returns the English content subtree' do
      amendment = described_class.new(publication_id: 'E.118', contents: contents)
      expect(amendment.contents_en).to eq(contents['en'])
    end

    it 'returns nil when contents is not a Hash' do
      amendment = described_class.new(publication_id: 'E.118', contents: nil)
      expect(amendment.contents_en).to be_nil
    end
  end

  describe '#slug' do
    it 'delegates to publication_id.slug' do
      amendment = described_class.new(publication_id: 'E.118', contents: contents)
      expect(amendment.slug).to eq(publication_id.slug)
    end
  end
end
