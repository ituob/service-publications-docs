# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Domain::TextAmendmentContent do
  let(:sample_doc) do
    {
      'type' => 'doc',
      'content' => [
        { 'type' => 'heading', 'attrs' => { 'level' => 3 },
          'content' => [{ 'type' => 'text', 'text' => 'Bureaufax Table' }] },
        { 'type' => 'paragraph',
          'content' => [{ 'type' => 'text', 'text' => 'Germany ADD' }] },
        { 'type' => 'table', 'content' => [
          { 'type' => 'table_row', 'content' => [
            { 'type' => 'table_cell', 'content' => [
              { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Country' }] },
            ] },
          ] },
        ] },
      ],
    }
  end

  subject(:content) { described_class.new(sample_doc) }

  it 'is frozen' do
    expect(content).to be_frozen
  end

  it 'rejects non-Hash input' do
    expect { described_class.new([]) }.to raise_error(TypeError)
    expect { described_class.new(nil) }.to raise_error(TypeError)
  end

  describe '#title' do
    it 'returns the first heading text' do
      expect(content.title).to eq('Bureaufax Table')
    end

    it 'returns nil when there are no headings' do
      doc = { 'type' => 'doc', 'content' => [{ 'type' => 'paragraph', 'content' => [] }] }
      expect(described_class.new(doc).title).to be_nil
    end
  end

  describe '#each_table' do
    it 'yields every table node' do
      count = content.each_table.count
      expect(count).to eq(1)
    end
  end

  describe '#action_paragraphs' do
    it 'finds paragraphs containing action keywords' do
      aps = content.action_paragraphs
      expect(aps.length).to eq(1)
      expect(aps.first[:action]).to eq('ADD')
      expect(aps.first[:text]).to include('Germany')
    end
  end

  describe '#body_chars' do
    it 'counts paragraph + table cell text' do
      # "Bureaufax Table" + "Germany ADD" + "Country"
      expect(content.body_chars).to be >= 25
    end
  end

  describe '#has_tables?' do
    it 'returns true when tables are present' do
      expect(content).to have_tables
    end

    it 'returns false when no tables' do
      doc = { 'type' => 'doc', 'content' => [{ 'type' => 'paragraph' }] }
      expect(described_class.new(doc)).not_to have_tables
    end
  end
end
