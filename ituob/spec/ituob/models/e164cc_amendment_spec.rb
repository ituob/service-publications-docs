# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::E164CCAmendment do
  def text_node(text, marks: nil)
    { 'type' => 'text', 'text' => text }.tap { |n| n['marks'] = marks if marks }
  end

  def paragraph(*texts)
    { 'type' => 'paragraph', 'content' => texts.map { |t| text_node(t) } }
  end

  def table(*rows)
    cells = ->(row) { row.map { |t| { 'type' => 'table_cell', 'content' => [paragraph(t)] } } }
    { 'type' => 'table', 'content' => rows.map { |r| { 'type' => 'table_row', 'content' => cells.(r) } } }
  end

  def action_types_for(marker)
    doc = { 'type' => 'doc', 'content' => [
      paragraph('Note p)', "  +883 320  #{marker}"),
      table(%w[Applicant Network Code Status], ['Tele2', 'Tele2', '+883 320', 'Withdrawn']),
    ] }
    described_class.parse(doc).actions.map(&:action_type).compact
  end

  %w[ADD SUP REP LIR].each do |type|
    it "keeps #{type} when the marker is bare" do
      expect(action_types_for(type)).to eq([type])
    end

    it "keeps #{type} when followed by one footnote asterisk" do
      expect(action_types_for("#{type}*")).to eq([type])
    end

    it "keeps #{type} when followed by two footnote asterisks" do
      expect(action_types_for("#{type}**")).to eq([type])
    end
  end

  it 'keeps ADD when followed by three footnote asterisks' do
    expect(action_types_for('ADD***')).to eq(['ADD'])
  end
end
