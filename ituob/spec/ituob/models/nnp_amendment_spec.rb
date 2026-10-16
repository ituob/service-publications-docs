# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::NNPAmendment do
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

  def listing_doc
    document(
      paragraph('Administrations are requested to notify ITU about their national numbering plan changes, on the understanding that the information will be published in the ITU Operational Bulletin.'),
      paragraph('From 1.V.2017 the following countries/geographical areas have updated their national numbering plans on the basis of information received:'),
      table(
        row(cell(paragraph('Country/ Geographical')), cell(paragraph('Country Code (CC)'))),
        row(cell(paragraph('Kosovo *')), cell(paragraph('+383'))),
        row(cell(paragraph('Kuwait')), cell(paragraph('+965'))),
      ),
    )
  end

  it 'lists each printed country/code row as an entry, verbatim' do
    entries = described_class.parse(listing_doc).actions.first.entries

    expect(entries.length).to eq(2)
    expect(entries.first.country_or_area.en).to eq('Kosovo *')
    expect(entries.first.country_code).to eq('+383')
    expect(entries.last.country_or_area.en).to eq('Kuwait')
    expect(entries.last.country_code).to eq('+965')
  end

  it 'skips the printed header row' do
    action = described_class.parse(listing_doc).actions.first

    expect(action.entries.map { |e| e.country_or_area.en }).not_to include('Country/ Geographical')
  end

  it 'collects the intro paragraphs (incl. the effective-date line) as notes' do
    notes = described_class.parse(listing_doc).notes

    expect(notes.length).to eq(2)
    expect(notes.first).to start_with('Administrations are requested')
    expect(notes.last).to start_with('From 1.V.2017')
  end

  it 'produces one listing action with numbering-plan entries' do
    amendment = described_class.parse(listing_doc)

    expect(amendment).to be_a(Ituob::Models::Amendment)
    expect(amendment.actions.length).to eq(1)
    expect(amendment.actions.first.entries.first).to be_a(Ituob::Models::NumberingPlanEntry)
  end

  it 'skips the stray single-cell "Country" header fragment' do
    doc = document(
      table(
        row(cell(paragraph('Country'))),
        row(cell(paragraph('Poland')), cell(paragraph('+48'))),
      ),
    )
    entries = described_class.parse(doc).actions.first.entries

    expect(entries.length).to eq(1)
    expect(entries.first.country_code).to eq('+48')
  end

  it 'parses a real source amendment (OB 1125)' do
    path = File.expand_path('../../../../itu-ob-data/issues/1125/amendments.yaml', __dir__)
    data = YAML.load_file(path, permitted_classes: [Date, Time])
    msg = data['messages'].find { |m| m['target']['publication'] == 'NNP' }
    parsed = described_class.parse(msg['contents']['en'])

    expect(parsed.actions.first.entries.map { |e| e.country_code }).to include('+383', '+965', '+48')
  end
end
