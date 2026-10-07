# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::E212MNCAmendment do
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

  def parse(doc)
    described_class.parse(doc)
  end

  it 'captures the printed country of a P line with no inline codes' do
    doc = document(
      paragraph('P  35   Rwanda ADD'),
      paragraph('      635 13    TIGO RWANDA LTD'),
    )
    entries = parse(doc).actions.first.entries

    expect(entries.length).to eq(1)
    expect(entries.first.country_or_area.en).to eq('Rwanda')
    expect(entries.first.mcc_mnc_codes).to eq('635 13')
    expect(entries.first.networks).to eq('TIGO RWANDA LTD')
  end

  it 'carries the country to later continuation paragraphs' do
    doc = document(
      paragraph('P  35   Rwanda ADD'),
      paragraph('      635 13    TIGO RWANDA LTD'),
      paragraph('      734 01    Infonet'),
    )
    entries = parse(doc).actions.first.entries

    expect(entries.length).to eq(2)
    expect(entries.last.mcc_mnc_codes).to eq('734 01')
    expect(entries.last.country_or_area.en).to eq('Rwanda')
  end

  it 'captures an entry printed on the P line itself' do
    doc = document(
      paragraph('P  9  Denmark ADD 238 66 Telenor'),
    )
    entries = parse(doc).actions.first.entries

    expect(entries.length).to eq(1)
    expect(entries.first.country_or_area.en).to eq('Denmark')
    expect(entries.first.mcc_mnc_codes).to eq('238 66')
    expect(entries.first.networks).to eq('Telenor')
  end

  it 'resets the inherited country between documents (no class-level state)' do
    doc_a = document(paragraph('P  35   Rwanda ADD'), paragraph('      635 13    TIGO'))
    doc_b = document(paragraph('      734 01    Infonet'))

    parse(doc_a)
    entries_b = parse(doc_b).actions.first.entries

    # doc_b's continuation has no P line, so no country leaks in from doc_a.
    expect(entries_b.first.country_or_area).to be_nil
  end

  it 'parses 3-column table rows with country in the first cell' do
    doc = document(
      table(
        row(cell(paragraph('Country/Geographical Area')), cell(paragraph('MCC+MNC')),
            cell(paragraph('Operator/Network'))),
        row(cell(paragraph('Belgium')), cell(paragraph('206 01')), cell(paragraph('Proximus'))),
      ),
    )
    amendment = parse(doc)

    expect(amendment.actions.length).to eq(2) # initial + post-table action
    expect(amendment.actions.first.entries.first.mcc_mnc_codes).to eq('206 01')
    expect(amendment.actions.first.entries.first.country_or_area.en).to eq('Belgium')
  end
end
