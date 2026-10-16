# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::Q708ISPCAmendment do
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

  # The source pads rows with non-breaking spaces; reproduce that here.
  NBSP = " "

  def parse(doc)
    described_class.parse(doc)
  end

  it 'creates the action from an in-table line with trailing padding' do
    doc = document(
      table(
        row(cell(paragraph('Germany')), cell(paragraph('ADD')), cell(paragraph(''))),
        row(cell(paragraph('2-129-7')), cell(paragraph('5135')),
            cell(paragraph('Frankfurt'))),
      ),
    )
    amendment = parse(doc)

    expect(amendment.actions.length).to eq(1)
    expect(amendment.actions.first.action_type).to eq('ADD')
    expect(amendment.actions.first.entries.length).to eq(1)
    expect(amendment.actions.first.entries.first.ipsc).to eq('2-129-7')
  end

  it 'parses "Country P N ACTION" action rows' do
    doc = document(
      table(
        row(cell(paragraph("#{NBSP}Country/ Geographical Area")), cell(paragraph('ISPC/DEC')),
            cell(paragraph('Unique name'))),
        row(cell(paragraph('Cambodia')), cell(paragraph('P  12  REP all information by:')),
            cell(paragraph(''))),
        row(cell(paragraph('4-112-0')), cell(paragraph('9088')), cell(paragraph('Bayon G1'))),
      ),
    )
    amendment = parse(doc)

    expect(amendment.actions.length).to eq(1)
    expect(amendment.actions.first.position).to eq('P 12')
    expect(amendment.actions.first.action_type).to eq('REP')
    expect(amendment.actions.first.entries.first.ipsc).to eq('4-112-0')
  end

  it 'parses "ACTION Country P N" action rows' do
    doc = document(
      table(
        row(cell(paragraph('ADD   Falkland Islands (Malvinas)  P  20')),
            cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('7-099-1')), cell(paragraph('15129')), cell(paragraph('ISC'))),
      ),
    )
    action = parse(doc).actions.first

    expect(action.action_type).to eq('ADD')
    expect(action.position).to eq('P 20')
    expect(action.entries.first.ipsc).to eq('7-099-1')
  end

  it 'skips blank rows and padded header rows without creating entries' do
    doc = document(
      table(
        row(cell(paragraph('Country/ Geographical Area')), cell(paragraph('Name')),
            cell(paragraph('Operator'))),
        row(cell(paragraph("#{NBSP} Company Name/Address")), cell(paragraph('(carrier code)')),
            cell(paragraph("#{NBSP}"))),
        row(cell(paragraph('')), cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('P  47    Hungary    ADD')), cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('2-212-6')), cell(paragraph('5798')), cell(paragraph('TELENOR INT 1'))),
      ),
    )
    amendment = parse(doc)

    expect(amendment.actions.length).to eq(1)
    expect(amendment.actions.first.entries.length).to eq(1)
    expect(amendment.actions.first.entries.first.ipsc).to eq('2-212-6')
  end

  it 'collects trilingual glossary notes' do
    doc = document(
      paragraph('____________'),
      paragraph('ISPC:      International Signalling Point Codes.'),
      paragraph('   Codes de points sémaphores internationaux (CPSI).'),
    )
    amendment = parse(doc)

    expect(amendment.notes).to include(a_string_starting_with('ISPC:'))
    expect(amendment.notes).to include(a_string_starting_with('Codes de'))
  end
end
