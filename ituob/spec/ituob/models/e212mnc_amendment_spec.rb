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

    # The post-table rollover action is typeless and empty — dropped.
    expect(amendment.actions.length).to eq(1)
    expect(amendment.actions.first.entries.first.mcc_mnc_codes).to eq('206 01')
    expect(amendment.actions.first.entries.first.country_or_area.en).to eq('Belgium')
  end

  it 'parses the editor layout: country rows carry the action for the rows that follow' do
    doc = document(
      table(
        row(cell(paragraph('Country / Geographical area'))),
        row(cell(paragraph('MCC + MNC')), cell(paragraph('Operator / Network'))),
        row(cell(paragraph("Canada   ADD"))),
        row(cell(paragraph('302 354')), cell(paragraph('Every-Day Computers Inc.'))),
        row(cell(paragraph("Canada   LIR"))),
        row(cell(paragraph('302 490')), cell(paragraph('Freedom Mobile Inc.'))),
        row(cell(paragraph('302 491')), cell(paragraph('Videotron Ltd.'))),
      ),
    )
    amendment = parse(doc)

    expect(amendment.actions.length).to eq(2)

    add = amendment.actions.first
    expect(add.action_type).to eq('ADD')
    expect(add.entries.length).to eq(1)
    expect(add.entries.first.country_or_area.en).to eq('Canada')
    expect(add.entries.first.mcc_mnc_codes).to eq('302 354')
    expect(add.entries.first.networks).to eq('Every-Day Computers Inc.')

    lir = amendment.actions.last
    expect(lir.action_type).to eq('LIR')
    expect(lir.entries.length).to eq(2)
    expect(lir.entries.map(&:country_or_area).map(&:en).uniq).to eq(['Canada'])
    expect(lir.entries.map(&:mcc_mnc_codes)).to eq(['302 490', '302 491'])
  end

  describe 'country-first paragraph layout (no position column)' do
    it 'opens one action per country line, keeping the printed action and country' do
      doc = document(
        paragraph("Belarus \u00a0\u00a0\u00a0SUP"),
        paragraph("\u00a0\u00a0\u00a0\u00a0\u00a0257 06\u00a0\u00a0\u00a0\u00a0\u00a0Yota Bel Foreign LLC"),
        paragraph("Qatar \u00a0\u00a0\u00a0ADD"),
        paragraph("\u00a0\u00a0\u00a0\u00a0\u00a0427 06\u00a0\u00a0\u00a0\u00a0\u00a0Ooredoo Q.S.C./MOI LTE"),
      )
      actions = parse(doc).actions

      expect(actions.map(&:action_type)).to eq(%w[SUP ADD])
      expect(actions.map { |a| a.entries.map(&:mcc_mnc_codes) }).to eq([['257 06'], ['427 06']])
      expect(actions.map { |a| a.entries.map { |e| e.country_or_area.en } }).to eq([['Belarus'], ['Qatar']])
    end

    it 'keeps each P line its own action instead of letting the last type win' do
      doc = document(
        paragraph('P  6  Canada SUP'),
        paragraph('      302 611    Bell Mobility'),
        paragraph('P  7  Canada ADD'),
        paragraph('      302 690    Bell Mobility'),
      )

      expect(parse(doc).actions.map(&:action_type)).to eq(%w[SUP ADD])
    end

    it 'keeps numbered operator lines under the code they follow' do
      doc = document(
        paragraph("P  30   Mexico ADD"),
        paragraph("      334 040    IUSACELL PCS DE MEXICO, S.A. DE C.V."),
        paragraph("      334 050    5 operators:"),
        paragraph("      1-COMUNICACIONES CELULARES DE OCCIDENTE, S.A. DE C.V."),
        paragraph("      3 -TELECOMUNICACIONES DEL GOLFO, S.A. DE C.V. SOS"),
        paragraph("      334 060    SERVICIOS DE ACCESO INALAMBRICO, S.A DE C.V."),
      )
      entries = parse(doc).actions.first.entries

      expect(entries.map(&:mcc_mnc_codes)).to eq(['334 040', '334 050', '334 060'])
      expect(entries[1].networks).to eq(
        "5 operators:\n1-COMUNICACIONES CELULARES DE OCCIDENTE, S.A. DE C.V.\n" \
        '3 -TELECOMUNICACIONES DEL GOLFO, S.A. DE C.V. SOS',
      )
      expect(entries[2].networks).to eq('SERVICIOS DE ACCESO INALAMBRICO, S.A DE C.V.')
    end

    it 'keeps the MSIN range of an extra-territorial table row' do
      doc = document(
        paragraph('Norway SUP'),
        paragraph('      242 06    ICE Norge AS'),
        paragraph("Sweden \u00a0(extra-territorial use of MCC/MNC, Annex E to ITU-T Recommendation E.212)"),
        table(
          row(cell(paragraph('MCC*/MNC**')), cell(paragraph('Name of operator(s)')), cell(paragraph('Countries A and B')),
              cell(paragraph('Country B')), cell(paragraph('MSIN range'))),
          row(cell(paragraph('240 07')), cell(paragraph('Tele 2 Sverige AB')), cell(paragraph('The Netherlands')),
              cell(paragraph('The range dedicated for the Netherlands will not be used in Sweden')),
              cell(paragraph('6680000000 -', '6689999999', '(The Netherlands)'))),
        ),
      )
      actions = parse(doc).actions
      entry = actions.last.entries.first

      expect(actions.map(&:action_type)).to eq(%w[SUP LIR])
      expect(actions.first.entries.map(&:mcc_mnc_codes)).to eq(['242 06'])
      expect(entry.mcc_mnc_codes).to eq('240 07')
      expect(entry.networks).to eq('Tele 2 Sverige AB')
      expect(entry.country_or_area.en).to eq('Sweden')
      expect(entry.range).to include('6680000000').and include('6689999999')
    end
  end
end
