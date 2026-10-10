# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Domain::ChangeObject do
  let(:issue_id) { Ituob::Domain::Identifiers::IssueId.new(1163) }
  let(:publication_id) { Ituob::Domain::Identifiers::PublicationId.new('E118_IIN') }
  let(:identifier) { Ituob::Domain::Identifiers::RecordCode.new('1163-001') }

  subject(:change_object) do
    described_class.new(
      action_type: 'ADD',
      issue_id: issue_id,
      publication_id: publication_id,
      identifier: identifier,
      data: { 'entries' => [{ 'country_or_area' => { 'en' => 'Germany' } }] },
    )
  end

  it 'is frozen' do
    expect(change_object).to be_frozen
  end

  describe '#filename' do
    it 'formats as NNN-ACTION.yaml' do
      expect(change_object.filename(sequence: 1)).to eq('001-ADD.yaml')
      expect(change_object.filename(sequence: 42)).to eq('042-ADD.yaml')
    end
  end

  describe '#to_h' do
    it 'produces the canonical change-object hash' do
      h = change_object.to_change_hash
      expect(h['type']).to eq('ADD')
      expect(h['ob_issue_no']).to eq('1163')
      expect(h['reference']).to eq('OB-1163')
      expect(h['identifier']['code']).to eq('1163-001')
      expect(h['data']['entries']).to be_an(Array)
    end
  end

  describe '#empty_entries?' do
    it 'returns true for entries: []' do
      co = described_class.new(
        action_type: 'ADD', issue_id: issue_id, publication_id: publication_id,
        identifier: identifier, data: { 'entries' => [] },
      )
      expect(co).to be_empty_entries
    end

    it 'returns true for entries: [{}]' do
      co = described_class.new(
        action_type: 'ADD', issue_id: issue_id, publication_id: publication_id,
        identifier: identifier, data: { 'entries' => [{}] },
      )
      expect(co).to be_empty_entries
    end

    it 'returns false for entries with real data' do
      expect(change_object).not_to be_empty_entries
    end
  end
end
