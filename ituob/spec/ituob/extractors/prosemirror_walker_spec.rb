# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Extractors::ProseMirrorWalker do
  let(:sample_doc) do
    {
      'type' => 'doc',
      'content' => [
        {
          'type' => 'paragraph',
          'content' => [{ 'type' => 'text', 'text' => 'Germany (Federal Republic of) ADD' }],
        },
        {
          'type' => 'table',
          'content' => [
            {
              'type' => 'table_row',
              'content' => [
                {
                  'type' => 'table_cell',
                  'content' => [
                    { 'type' => 'paragraph',
                      'content' => [{ 'type' => 'text', 'text' => 'Country' }] },
                  ],
                },
                {
                  'type' => 'table_cell',
                  'content' => [
                    { 'type' => 'paragraph',
                      'content' => [{ 'type' => 'text', 'text' => 'Code' }] },
                  ],
                },
              ],
            },
            {
              'type' => 'table_row',
              'content' => [
                {
                  'type' => 'table_cell',
                  'content' => [
                    { 'type' => 'paragraph',
                      'content' => [{ 'type' => 'text', 'text' => 'Germany' }] },
                  ],
                },
                {
                  'type' => 'table_cell',
                  'content' => [
                    { 'type' => 'paragraph',
                      'content' => [{ 'type' => 'text', 'text' => 'AMABO' }] },
                  ],
                },
              ],
            },
          ],
        },
      ],
    }
  end

  describe '.each_top_level' do
    it 'yields the top-level children of the doc' do
      types = []
      described_class.each_top_level(sample_doc) { |n| types << n['type'] }
      expect(types).to eq(%w[paragraph table])
    end
  end

  describe '.node_text' do
    it 'extracts concatenated text' do
      text = described_class.node_text(sample_doc['content'].first)
      expect(text).to eq('Germany (Federal Republic of) ADD')
    end
  end

  describe '.extract_rows' do
    it 'returns rows of cell-text arrays' do
      table = sample_doc['content'].last
      rows = described_class.extract_rows(table)
      expect(rows.length).to eq(2)
      expect(rows.first).to eq(%w[Country Code])
      expect(rows.last).to eq(%w[Germany AMABO])
    end
  end

  describe '.normalize_ws' do
    it 'collapses whitespace' do
      expect(described_class.normalize_ws("  foo\tbar  \n baz  "))
        .to eq('foo bar baz')
      expect(described_class.normalize_ws(nil)).to eq('')
    end
  end
end
