# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::E118Amendment do
  def paragraph(text)
    { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
  end

  def table(*rows)
    cells = ->(row) { row.map { |t| { 'type' => 'table_cell', 'attrs' => { 'rowspan' => 1 }, 'content' => [paragraph(t)] } } }
    { 'type' => 'table', 'content' => rows.map { |r| { 'type' => 'table_row', 'content' => cells.(r) } } }
  end

  it 'keeps the tables of two identical heading paragraphs' do
    doc = { 'type' => 'doc', 'content' => [
      paragraph('P 67 United States ADD'),
      table(['United States', 'Alpha Co', '89 1 111']),
      paragraph('P 67 United States ADD'),
      table(['United States', 'Beta Co', '89 1 222']),
    ] }

    actions = described_class.parse(doc).actions

    expect(actions.size).to eq(2)
    expect(actions.map { |a| a.entries.first.to_json }.join).to include('Alpha Co').and include('Beta Co')
  end
end
