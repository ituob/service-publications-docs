# frozen_string_literal: true

require 'spec_helper'
require 'ituob/domain'

RSpec.describe Ituob::Domain::Issue do
  let(:amendment) do
    Ituob::Domain::Amendment.new(
      publication_id: 'E.118',
      contents: { 'en' => {} },
    )
  end
  let(:general_messages) do
    [{ type: 'approved_recommendations', contents: {} }]
  end

  describe '#initialize' do
    it 'coerces numeric id to IssueId' do
      issue = described_class.new(id: 1000)
      expect(issue.id).to be_a(Ituob::Domain::Identifiers::IssueId)
    end

    it 'accepts an IssueId directly' do
      issue_id = Ituob::Domain::Identifiers::IssueId.new(1000)
      issue = described_class.new(id: issue_id)
      expect(issue.id).to eq(issue_id)
    end

    it 'defaults general_messages and amendments to empty arrays' do
      issue = described_class.new(id: 1000)
      expect(issue.general_messages).to eq([])
      expect(issue.amendments).to eq([])
    end
  end

  describe '#each_publication_id' do
    it 'yields each amendment publication_id' do
      issue = described_class.new(id: 1000, amendments: [amendment])
      expect { |b| issue.each_publication_id(&b) }.to yield_control.once
    end

    it 'returns an enumerator when no block given' do
      issue = described_class.new(id: 1000, amendments: [amendment])
      expect(issue.each_publication_id).to be_an(Enumerator)
    end
  end

  describe '#each_general_type' do
    it 'yields each general message type' do
      issue = described_class.new(id: 1000, general_messages: general_messages)
      expect { |b| issue.each_general_type(&b) }.to yield_with_args('approved_recommendations')
    end

    it 'returns an enumerator when no block given' do
      issue = described_class.new(id: 1000, general_messages: general_messages)
      expect(issue.each_general_type).to be_an(Enumerator)
    end
  end
end
