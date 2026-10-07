# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::DPAmendment do
  def text_node(text)
    { 'type' => 'text', 'text' => text }
  end

  def paragraph(*texts)
    { 'type' => 'paragraph', 'content' => texts.map { |t| text_node(t) } }
  end

  def cell(*paragraphs)
    { 'type' => 'table_cell', 'content' => paragraphs }
  end

  def row(*cells)
    { 'type' => 'table_row', 'content' => cells }
  end

  def table(*rows)
    { 'type' => 'table', 'content' => rows }
  end

  def document(*blocks)
    { 'type' => 'doc', 'content' => blocks }
  end

  def header_row
    row(
      cell(paragraph('Country/ geographical area')), cell(paragraph('Country code')),
      cell(paragraph('International prefix')), cell(paragraph('National prefix')),
      cell(paragraph('National (significant) number')), cell(paragraph('UTC/DST')),
      cell(paragraph('Note')),
    )
  end

  def dp_doc
    document(
      table(header_row),
      paragraph(''),
      paragraph('P  4   Djibouti LIR'),
      table(
        row(
          cell(paragraph('Djibouti')), cell(paragraph('253')), cell(paragraph('00')),
          cell(paragraph('0')), cell(paragraph('8 digits')), cell(paragraph('+3')),
          cell(paragraph('')),
        ),
      ),
    )
  end

  it 'reads the P line into position, country, and action type' do
    action = described_class.parse(dp_doc).actions.first

    expect(action.position).to eq('P 4')
    expect(action.country).to eq('Djibouti')
    expect(action.action_type).to eq('LIR')
    expect(action.description).to eq('P 4 Djibouti LIR')
  end

  it 'extracts the full 7-column plan row as a NumberingPlanEntry' do
    entry = described_class.parse(dp_doc).actions.first.entries.first

    expect(entry).to be_a(Ituob::Models::NumberingPlanEntry)
    expect(entry.country_or_area.en).to eq('Djibouti')
    expect(entry.country_code).to eq('253')
    expect(entry.international_prefix).to eq('00')
    expect(entry.national_prefix).to eq('0')
    expect(entry.national_sig_number).to eq('8 digits')
    expect(entry.utc_dst).to eq('+3')
  end

  it 'skips the printed header table and empty paragraphs' do
    parsed = described_class.parse(dp_doc)

    expect(parsed.actions.first.entries.length).to eq(1)
    expect(parsed.notes).to be_empty
  end

  it 'collects non-P paragraphs as notes' do
    doc = document(paragraph('See also page 8 of this Bulletin.'))
    expect(described_class.parse(doc).notes).to include(a_string_starting_with('See also'))
  end

  it 'parses a real source amendment (OB 1000)' do
    path = File.expand_path('../../../../itu-ob-data/issues/1000/amendments.yaml', __dir__)
    data = YAML.load_file(path, permitted_classes: [Date, Time])
    msg = data['messages'].find { |m| m['target']['publication'] == 'DP' }
    parsed = described_class.parse(msg['contents']['en'])
    entry = parsed.actions.first.entries.first

    expect(parsed.actions.first.action_type).to eq('LIR')
    expect(entry.country_or_area.en).to eq('Djibouti')
    expect(entry.country_code).to eq('253')
    expect(entry.utc_dst).to eq('+3')
  end
end
