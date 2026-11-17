# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'
require 'timeout'

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

  describe 'rowspan heading layout (OB 1176)' do
    # "«country» ACTION" sits in a rowspan cell beside blank code and
    # network cells; the code/network rows below it have two cells.
    def heading(text)
      row(cell(paragraph(text)), cell(paragraph(" ")), cell(paragraph(" ")))
    end

    def pair(code, network)
      row(cell(paragraph(code)), cell(paragraph(network)))
    end

    let(:amendment) do
      parse(document(table(
        row(cell(paragraph('Country/Geographical area')), cell(paragraph('MCC+MNC *')),
            cell(paragraph('Operator/Network'))),
        heading('Denmark ADD'), pair('238 96', 'Telia Danmark'),
        heading('South Africa SUP'), pair('655 04', 'Sasol (Pty) Ltd'), pair('655 11', 'SAPS Gauteng'),
        heading('International Mobile, shared code LIR *'), pair('901 53', 'Tele2 Sverige AB')
      )))
    end

    it 'opens one typed action per heading instead of a blank-key entry' do
      expect(amendment.actions.map(&:action_type)).to eq(%w[ADD REP LIR])
      codes = amendment.actions.flat_map(&:entries).map(&:mcc_mnc_codes)
      expect(codes).to eq(['238 96', '655 04', '655 11', '901 53'])
    end

    it 'carries the heading country to every printed row under it' do
      countries = amendment.actions.map { |action| action.entries.map { |e| e.country_or_area.en }.uniq }
      expect(countries).to eq([['Denmark'], ['South Africa'], ['International Mobile, shared code']])
    end

    it 'reads a heading that is the first row of a later table' do
      first = table(heading('Kosovo* ADD'), pair('221 01', 'Tel'))
      second = table(heading('Spain SUP'), pair('214 10', 'Opera'))
      actions = parse(document(first, second)).actions

      expect(actions.map(&:action_type)).to eq(%w[ADD REP])
      expect(actions.last.entries.map { |e| e.country_or_area.en }).to eq(['Spain'])
      expect(actions.last.entries.map(&:mcc_mnc_codes)).to eq(['214 10'])
    end

    it 'still skips a first row that is a column header' do
      header = row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Operator')))
      amendment = parse(document(table(header, heading('Denmark ADD'), pair('238 96', 'Telia'))))

      expect(amendment.actions.flat_map(&:entries).map(&:mcc_mnc_codes)).to eq(['238 96'])
    end

    it 'reads ideographic and zero-width blank cells as a heading row' do
      expect(described_class.rowspan_heading(['Denmark ADD', "\u3000", "\u200B"]))
        .to eq(country: 'Denmark', action: 'ADD')
    end

    it 'never turns a heading-like row with no code into a blank-key entry' do
      doc = document(table(heading('Denmark add'), pair('238 96', 'Telia')))
      codes = parse(doc).actions.flat_map(&:entries).map(&:mcc_mnc_codes)

      expect(codes).to eq(['238 96'])
    end

    it 'leaves no empty action behind two consecutive headings' do
      amendment = parse(document(table(
        row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Operator'))),
        heading('Denmark ADD'), heading('Norway SUP'), pair('578 01', 'N')
      )))

      expect(amendment.actions.map(&:action_type)).to eq(%w[REP])
    end

    it 'returns nil for an empty segment list' do
      expect(described_class.rowspan_heading([])).to be_nil
    end

    it 'still reads a three-cell row with a code as an entry' do
      doc = document(table(heading('Denmark ADD'),
                           row(cell(paragraph('Denmark')), cell(paragraph('238 97')), cell(paragraph('Net')))))
      entries = parse(doc).actions.flat_map(&:entries)
      expect(entries.map(&:mcc_mnc_codes)).to eq(['238 97'])
    end
  end

  it 'carries table headings through consecutive rows and switches at the next heading' do
    doc = document(
      table(
        row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Network'))),
        row(cell(paragraph('Hungary SUP')), cell(paragraph("\u00a0")), cell(paragraph(' '))),
        row(cell(paragraph('')), cell(paragraph('216 04')), cell(paragraph('First network'))),
        row(cell(paragraph('')), cell(paragraph('216 05')), cell(paragraph('Second network'))),
        row(cell(paragraph('Kenya ADD'))),
        row(cell(paragraph('639 08')), cell(paragraph('Third network'))),
      ),
    )
    actions = parse(doc).actions

    expect(actions.map(&:action_type)).to eq(%w[REP ADD])
    expect(actions.map { |action| action.entries.map { |entry| entry.country_or_area.en } }).to eq(
      [%w[Hungary Hungary], ['Kenya']],
    )
    expect(actions.flat_map(&:entries).map(&:mcc_mnc_codes)).to eq(['216 04', '216 05', '639 08'])
  end

  it 'skips normalized blank keys in multi-line and four-column rows' do
    doc = document(
      table(
        row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Network'))),
        row(cell(paragraph('Hungary SUP'))),
        row(cell(paragraph('')), cell(paragraph("\u00a0"), paragraph('216 04')),
            cell(paragraph(''), paragraph('Invitech ICT Services Ltd.'))),
        row(cell(paragraph('')), cell(paragraph(" \u00a0 ")), cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('')), cell(paragraph('216 05')), cell(paragraph('1-9')), cell(paragraph('Another network'))),
      ),
    )
    amendment = parse(doc)
    entries = amendment.actions.flat_map(&:entries)

    expect(amendment.actions.map(&:action_type)).to eq(['REP'])
    expect(entries.map(&:mcc_mnc_codes)).to eq(['216 04', '216 05'])
    expect(entries.map { |entry| entry.country_or_area.en }).to eq(%w[Hungary Hungary])
    expect(entries.map(&:networks)).to eq(['Invitech ICT Services Ltd.', 'Another network'])
    expect(entries.last.range).to eq('1-9')
  end

  %w[paragraph table].each do |layout|
    it "prefers printed row countries after a #{layout} country heading" do
      heading = if layout == 'paragraph'
                  paragraph('Hungary ADD')
                else
                  table(
                    row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Network'))),
                    row(cell(paragraph('Hungary ADD'))),
                    row(cell(paragraph('216 04')), cell(paragraph('Hungarian network'))),
                  )
                end
      doc = document(
        heading,
        table(
          row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Network'))),
          row(cell(paragraph('Belgium')), cell(paragraph('206 01')), cell(paragraph('Proximus'))),
          row(cell(paragraph('Belgium')), cell(paragraph('206 02'), paragraph('206 03')),
              cell(paragraph('Second network'), paragraph('Third network'))),
        ),
        table(
          row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Range')), cell(paragraph('Network'))),
          row(cell(paragraph('Belgium')), cell(paragraph('206 04')), cell(paragraph('1-9')), cell(paragraph('Fourth network'))),
        ),
      )
      entries = parse(doc).actions.flat_map(&:entries).select { |entry| entry.mcc_mnc_codes.start_with?('206') }

      expect(entries.map(&:mcc_mnc_codes)).to eq(['206 01', '206 02', '206 03', '206 04'])
      expect(entries.map { |entry| entry.country_or_area.en }).to eq(Array.new(4, 'Belgium'))
    end
  end

  it 'carries a printed rowspan country onto its two-cell continuation rows' do
    doc = document(
      table(
        row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Network'))),
        row(cell(paragraph('Hungary ADD'))),
        row(cell(paragraph('216 04')), cell(paragraph('Hungarian network'))),
        row(cell(paragraph('Belgium')).merge('attrs' => { 'rowspan' => 2 }),
            cell(paragraph('206 01')), cell(paragraph('Proximus'))),
        row(cell(paragraph('206 02')), cell(paragraph('Belgian continuation'))),
        row(cell(paragraph('Netherlands')).merge('attrs' => { 'rowspan' => 2 }),
            cell(paragraph('204 01'), paragraph('204 02')),
            cell(paragraph('First Dutch network'), paragraph('Second Dutch network'))),
        row(cell(paragraph('204 03')), cell(paragraph('Dutch continuation'))),
      ),
    )
    actions = parse(doc).actions
    entries = actions.flat_map(&:entries)

    expect(actions.map(&:action_type)).to eq(['ADD'])
    expect(entries.map(&:mcc_mnc_codes)).to eq(['216 04', '206 01', '206 02', '204 01', '204 02', '204 03'])
    expect(entries.map { |entry| entry.country_or_area.en }).to eq(
      %w[Hungary Belgium Belgium Netherlands Netherlands Netherlands],
    )
    expect(entries.values_at(2, 5).map(&:networks)).to eq(['Belgian continuation', 'Dutch continuation'])
  end

  it 'carries a four-column row country into a later two-column table' do
    doc = document(
      paragraph('Hungary ADD'),
      table(
        row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Range')), cell(paragraph('Network'))),
        row(cell(paragraph('Belgium')), cell(paragraph('206 01')), cell(paragraph('1-9')), cell(paragraph('Proximus'))),
      ),
      table(
        row(cell(paragraph('MCC+MNC')), cell(paragraph('Network'))),
        row(cell(paragraph('206 02')), cell(paragraph('Belgian continuation'))),
        row(cell(paragraph('206 03')), cell(paragraph('Another Belgian continuation'))),
      ),
    )
    entries = parse(doc).actions.flat_map(&:entries)

    expect(entries.map(&:mcc_mnc_codes)).to eq(['206 01', '206 02', '206 03'])
    expect(entries.map { |entry| entry.country_or_area.en }).to eq(%w[Belgium Belgium Belgium])
    expect(entries.first.range).to eq('1-9')
  end

  it 'recognizes multi-cell country headings with parentheses' do
    doc = document(
      table(
        row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Network'))),
        row(cell(paragraph('Hungary ADD')), cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('216 04')), cell(paragraph('Hungarian network'))),
        row(cell(paragraph('Iran (Islamic Republic of) SUP')), cell(paragraph("\u00a0")), cell(paragraph(' '))),
        row(cell(paragraph('432 11')), cell(paragraph('Iranian network'))),
        row(cell(paragraph("\u00a0")), cell(paragraph('432 12')), cell(paragraph('Another Iranian network'))),
      ),
    )
    actions = parse(doc).actions

    expect(actions.map(&:action_type)).to eq(%w[ADD REP])
    expect(actions.map { |action| action.entries.map(&:mcc_mnc_codes) }).to eq([['216 04'], ['432 11', '432 12']])
    expect(actions.last.entries.map { |entry| entry.country_or_area.en }).to eq(
      ['Iran (Islamic Republic of)', 'Iran (Islamic Republic of)'],
    )
    expect(actions.last.entries.map(&:networks)).to eq(['Iranian network', 'Another Iranian network'])
  end

  it 'classifies single-cell editor SUP headings as replacement blocks' do
    doc = document(
      table(
        row(cell(paragraph('Country / Geographical area'))),
        row(cell(paragraph('MCC + MNC')), cell(paragraph('Operator / Network'))),
        row(cell(paragraph("Iran (Islamic Republic of)\u00a0 SUP"))),
        row(cell(paragraph('432 11')), cell(paragraph('Iranian network'))),
      ),
    )
    actions = parse(doc).actions

    expect(actions.map(&:action_type)).to eq(['REP'])
    expect(actions.first.entries.map(&:mcc_mnc_codes)).to eq(['432 11'])
    expect(actions.first.entries.first.country_or_area.en).to eq('Iran (Islamic Republic of)')
  end

  it 'preserves starred actions in multi-cell country headings' do
    doc = document(
      table(
        row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Network'))),
        row(cell(paragraph('Hungary SUP*')), cell(paragraph('')), cell(paragraph(''))),
        row(cell(paragraph('216 04')), cell(paragraph('Hungarian network'))),
      ),
    )
    actions = parse(doc).actions

    expect(actions.map(&:action_type)).to eq(['REP'])
    expect(actions.first.entries.map(&:mcc_mnc_codes)).to eq(['216 04'])
    expect(actions.first.entries.first.country_or_area.en).to eq('Hungary')
  end

  [' ', "\u00a0"].each do |separator|
    it "opens a separate country block when #{separator.inspect} separates the action from its star" do
      doc = document(
        table(
          row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Network'))),
          row(cell(paragraph('Sweden LIR')), cell(paragraph(' ')), cell(paragraph(' '))),
          row(cell(paragraph('')), cell(paragraph('240 14')), cell(paragraph('Tele2'))),
          row(cell(paragraph("International Mobile, shared code LIR#{separator}*")),
              cell(paragraph(' ')), cell(paragraph(' '))),
          row(cell(paragraph('')), cell(paragraph('901 53')), cell(paragraph('Inmarsat'))),
        ),
      )
      actions = parse(doc).actions

      expect(actions.map do |action|
        [action.action_type, action.entries.map do |entry|
          [entry.country_or_area.en, entry.mcc_mnc_codes, entry.networks]
        end]
      end).to eq([
        ['LIR', [['Sweden', '240 14', 'Tele2']]],
        ['LIR', [['International Mobile, shared code', '901 53', 'Inmarsat']]],
      ])
    end
  end

  context 'OB 1170 table announcements' do
    let(:amendment) do
      parse(YAML.safe_load_file(File.expand_path('../../fixtures/e212mnc/ob1170.yaml', __dir__)))
    end
    let(:entries) { amendment.actions.flat_map(&:entries) }

    it 'drops the blank heading keys and preserves the printed entries' do
      expect(entries.map(&:mcc_mnc_codes)).to eq(['216 04', '639 08'])
      expect(entries.map(&:networks)).to eq(['Invitech ICT Services Ltd.', 'Sema Mobile Services Limited'])
    end

    it 'stamps each entry with its block country' do
      expect(entries.map { |entry| entry.country_or_area&.en }).to eq(['Hungary', 'Kenya'])
    end

    it 'replaces the listed codes in country SUP blocks' do
      expect(amendment.actions.map(&:action_type)).to eq(%w[REP REP])
      expect(amendment.actions.map { |action| action.entries.map(&:mcc_mnc_codes) }).to eq([['216 04'], ['639 08']])
    end
  end

  describe 'country-first paragraph layout (no position column)' do
    it 'opens an action with the full parenthesised country heading' do
      doc = document(
        paragraph('Germany (Federal Republic of)   ADD*'),
        paragraph('      262 01    Telekom Deutschland GmbH'),
      )
      actions = parse(doc).actions

      expect(actions.length).to eq(1)
      expect(actions.first.action_type).to eq('ADD')
      expect(actions.first.entries.first.country_or_area.en).to eq('Germany (Federal Republic of)')
      expect(actions.first.entries.first.mcc_mnc_codes).to eq('262 01')
    end

    it 'keeps a parenthesised SUP heading out of the preceding country action' do
      doc = document(
        paragraph('Estonia ADD'),
        paragraph('      248 01    AS Eesti Telekom'),
        paragraph('Moldova (Republic of) SUP'),
        paragraph('      259 04    Eventis Mobile GSM'),
      )
      actions = parse(doc).actions

      expect(actions.map(&:action_type)).to eq(%w[ADD SUP])
      expect(actions.first.entries.map(&:mcc_mnc_codes)).to eq(['248 01'])
      expect(actions.last.entries.first.country_or_area.en).to eq('Moldova (Republic of)')
      expect(actions.last.entries.first.mcc_mnc_codes).to eq('259 04')
    end

    it 'rejects long runs of spaces and NBSP within two seconds' do
      doc = document(paragraph(" \u00a0" * 100_000))

      Timeout.timeout(2) do
        expect(parse(doc).actions).to be_empty
        expect(described_class.country_action_line("Germany#{' ' * 200_000}UNKNOWN")).to be_nil
        expect(described_class.country_action_line("Germany#{' ' * 200_000}ADD")).to eq(
          country: 'Germany', action: 'ADD',
        )
      end
    end

    it 'preserves the country guards and the 64-character limit' do
      ['germany', 'Germany 2', 'Germany:', 'P 35 Germany', 'A' * 65, ''].each do |country|
        expect(described_class.country_action_line("#{country} ADD")).to be_nil
      end

      expect(described_class.country_action_line("#{'A' * 64} ADD")).to eq(
        country: 'A' * 64, action: 'ADD',
      )
      expect(described_class.country_action_line('GermanyADD')).to be_nil
      expect(described_class.country_action_line('Germany MOD')).to be_nil
    end

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

  describe 'E.212 print shapes found in the corpus' do
    def heading(text)
      row(cell(paragraph(text)), cell(paragraph(' ')), cell(paragraph(' ')))
    end

    def pair(code, network)
      row(cell(paragraph(code)), cell(paragraph(network)))
    end

    def source_entries(issue, position_on: nil)
      path = File.expand_path("../../../../itu-ob-data/issues/#{issue}/amendments.yaml", __dir__)
      skip 'itu-ob-data submodule not checked out' unless File.exist?(path)

      data = YAML.load_file(path, permitted_classes: [Date, Time])
      msgs = data['messages'].select { |m| m['target']['publication'] == 'E212_MNC' }
      parse(msgs.first['contents']['en'])
    end

    it 'recognises the 58-character French Indian Ocean country lines (OB 1087)' do
      expect(described_class.country_action_line(
        'French Departments and Territories in the Indian Ocean SUP',
      )).to eq(country: 'French Departments and Territories in the Indian Ocean', action: 'SUP')

      actions = source_entries(1087).actions
      by_type = actions.select { |a| a.entries.any? { |e| e.mcc_mnc_codes.start_with?('647') } }
      expect(by_type.map { |a| [a.action_type, a.entries.map(&:mcc_mnc_codes)] })
        .to eq([['SUP', ['647 02']], ['ADD', ['647 01', '647 02']]])
    end

    it 'skips a column header repeated inside a table' do
      header = row(cell(paragraph('Country/Geographical area')), cell(paragraph('MCC+MNC *')),
                   cell(paragraph('Operator/Network')))
      doc = document(table(header, heading('Denmark SUP'), pair('238 96', 'Telia'), header,
                           pair('238 97', 'Tele2')))
      entries = parse(doc).actions.flat_map(&:entries)

      expect(entries.map(&:mcc_mnc_codes)).to eq(['238 96', '238 97'])
    end

    it 'keeps the operator and range of a country cell with a (Country A) qualifier (OB 1348)' do
      entries = source_entries(1348).actions.flat_map(&:entries)
      germany = entries.find { |e| e.country_or_area.en == 'Germany' }

      expect([germany.mcc_mnc_codes, germany.range, germany.networks])
        .to eq(['262 74', '0000099000 - 0000099099', 'Ericsson GmbH'])
      expect(entries.map(&:mcc_mnc_codes)).not_to include(a_string_starting_with('('))
      expect(entries.map(&:mcc_mnc_codes)).not_to include(a_string_matching(/\AMCC\+MNC/))
    end

    it 'records a Country B row as extra-territorial use on the Country A entry (OB 1348)' do
      entries = source_entries(1348).actions.flat_map(&:entries).select { |e| e.mcc_mnc_codes == '262 74' }

      expect(entries.length).to eq(1)
      expect(entries.first.country_or_area.en).to eq('Germany')
      expect(entries.first.note.en).to start_with(
        "Extra-territorial use in Sweden (Country B – Where the MCC+MNC is to be used " \
        'extra‑territorially): Ericsson GmbH; MSIN range 0000099100 - 0000099199'
      )
      expect(entries.first.extra_territorial_use).to be(true)
      expect(entries.first.note.en).to include('***', 'As defined in Annex E')
    end

    it 'splits an inline qualifier from the country name and pairs Country B rows (OB 1108)' do
      entries = source_entries(1108).actions.flat_map(&:entries).select { |e| e.mcc_mnc_codes.start_with?('208') }

      expect(entries.map { |e| [e.mcc_mnc_codes, e.country_or_area.en] })
        .to eq([['208 10', 'France'], ['208 20', 'France']])
      expect(entries.map { |e| e.note.en }).to all(start_with('Extra-territorial use'))
      expect(entries.first.note.en).to include('Extra-territorial use in Monaco (Country B')
    end

    it 'does not read the column header under a title row as an entry (OB 1108, OB 1094)' do
      [1108, 1094].each do |issue|
        codes = source_entries(issue).actions.flat_map(&:entries).map(&:mcc_mnc_codes)

        expect(codes).not_to include(a_string_matching(/\AMCC\+MNC/))
      end
    end

    ['MCC+MNC*', 'MCC*/MNC**'].each do |code_label|
      it "skips a #{code_label} header after a title while preserving the data row" do
        title = row(cell(paragraph('Extra-territorial use of MCC+MNC')))
        header = row(cell(paragraph('Country or Geographical Area')), cell(paragraph(code_label)),
                     cell(paragraph('MSIN range')), cell(paragraph('Operator 1')))
        data = row(cell(paragraph('France'), paragraph('(Country A)')),
                   cell(paragraph('208 01')), cell(paragraph('A')), cell(paragraph('Orange')))
        entries = parse(document(table(title, header, data))).actions.flat_map(&:entries)

        expect(entries.map { |entry| [entry.mcc_mnc_codes, entry.networks, entry.range] })
          .to eq([['208 01', 'Orange', 'A']])
      end
    end

    # A row 1 holding a code is a data row under the title, not a header:
    # each shape below was dropped as a header before the fix.
    [
      ['310 260*', 'footnote star on the code'],
      ['310 260 / 310 270', 'two codes in one cell'],
      ['310260', 'code without the space'],
      ['310 260, 310 270', 'comma-separated codes'],
      ['310 26A', 'letter in the code'],
      ['—', 'a printed dash placeholder']
    ].each do |code, shape|
      it "keeps a data row under a single-cell title when the code has #{shape} (#{code})" do
        title = row(cell(paragraph('Extra-territorial use of MCC+MNC')))
        data = row(cell(paragraph('Sweden')), cell(paragraph(code)), cell(paragraph('A')), cell(paragraph('Op A')))
        following = row(cell(paragraph('Sweden')), cell(paragraph('310 270')),
                        cell(paragraph('A')), cell(paragraph('Op B')))
        entries = parse(document(table(title, data, following))).actions.flat_map(&:entries)

        expect(entries.map(&:mcc_mnc_codes)).to eq([code, '310 270'])
      end
    end

    it 'keeps a Country B row with no matching Country A code as its own entry' do
      header = row(cell(paragraph('Country or Geographical Area')), cell(paragraph('MCC+MNC')),
                   cell(paragraph('MSIN range')), cell(paragraph('Operators Name')))
      sweden = row(cell(paragraph('Sweden'), paragraph('(Country B – extra-territorial)')),
                   cell(paragraph('262 74')), cell(paragraph('1 - 2')), cell(paragraph('Ericsson')))
      doc = document(table(header, sweden))
      entry = parse(doc).actions.flat_map(&:entries).first

      expect([entry.country_or_area.en, entry.note.en]).to eq(['Sweden', '(Country B – extra-territorial)'])
    end

    it 'does not attach a Country B row to a plain row that shares its code' do
      header = row(cell(paragraph('Country or Geographical Area')), cell(paragraph('MCC+MNC')),
                   cell(paragraph('MSIN range')), cell(paragraph('Operators Name')))
      plain = row(cell(paragraph('France')), cell(paragraph('208 01')), cell(paragraph('A')), cell(paragraph('Plain Op')))
      monaco = row(cell(paragraph('Monaco'), paragraph('(Country B – extra)')),
                   cell(paragraph('208 01')), cell(paragraph('B')), cell(paragraph('OpB')))
      entries = parse(document(table(header, plain, monaco))).actions.flat_map(&:entries)

      expect(entries.map { |e| [e.country_or_area.en, e.note&.en] })
        .to eq([['France', nil], ['Monaco', '(Country B – extra)']])
    end

    it 'keeps two Country B rows sharing a code without a Country A row as separate entries' do
      header = row(cell(paragraph('Country or Geographical Area')), cell(paragraph('MCC+MNC')),
                   cell(paragraph('MSIN range')), cell(paragraph('Operators Name')))
      first = row(cell(paragraph('Monaco'), paragraph('(Country B – x)')),
                  cell(paragraph('208 01')), cell(paragraph('B1')), cell(paragraph('Op1')))
      second = row(cell(paragraph('Andorra'), paragraph('(Country B – y)')),
                   cell(paragraph('208 01')), cell(paragraph('B2')), cell(paragraph('Op2')))
      entries = parse(document(table(header, first, second))).actions.flat_map(&:entries)

      expect(entries.map { |e| [e.country_or_area.en, e.note.en] })
        .to eq([['Monaco', '(Country B – x)'], ['Andorra', '(Country B – y)']])
    end

    it 'keeps cells past the fourth on a Country B row' do
      header = row(cell(paragraph('Country or Geographical Area')), cell(paragraph('MCC+MNC')),
                   cell(paragraph('MSIN range')), cell(paragraph('Operators Name')))
      france = row(cell(paragraph('France'), paragraph('(Country A)')),
                   cell(paragraph('208 01')), cell(paragraph('A')), cell(paragraph('OpA')))
      monaco = row(cell(paragraph('Monaco'), paragraph('(Country B – x)')),
                   cell(paragraph('208 01')), cell(paragraph('B')), cell(paragraph('OpB')), cell(paragraph('EXTRA5')))
      entry = parse(document(table(header, france, monaco))).actions.flat_map(&:entries).first

      expect(entry.note.en).to end_with('Monaco (Country B – x): OpB; MSIN range B; EXTRA5')
    end

    it 'reads left-to-right marks, word joiners and soft hyphens as blank cells' do
      ["\u200E", "\u200F", "\u2060", "\u00AD"].each do |mark|
        expect(described_class.rowspan_heading(['Denmark ADD', mark, ' ']))
          .to eq(country: 'Denmark', action: 'ADD')
      end
    end
  end

  describe 'printed footnotes and extra-territorial details' do
    let(:header) do
      row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')), cell(paragraph('Operator/Network')))
    end

    it 'applies an As from footnote only to its preceding announcement (OB 989, 1008)' do
      doc = document(paragraph('P 1 Australia ADD'),
                     table(header, row(cell(paragraph('Australia')), cell(paragraph('505 20')), cell(paragraph('Ausgrid')))),
                     paragraph('P 17 International Mobile, shared code ADD 1'),
                     table(header, row(cell(paragraph('International Mobile, shared code')), cell(paragraph('901 33')),
                                       cell(paragraph('Smart Communications')))),
                     paragraph('1 As from 31 August 2011'))
      actions = parse(doc).actions

      expect(actions.map { |a| a.entries.first.effective_date }).to eq([nil, '31 August 2011'])
      expect(actions.map { |a| a.entries.first.mcc_mnc_codes }).to eq(['505 20', '901 33'])
      expect(parse(doc).notes).to include('1 As from 31 August 2011')
    end

    it 'keeps an inline country-first announcement separate from the following country (OB 1062)' do
      parsed = parse(document(paragraph('Malta ADD 278 11 YOM'),
                              paragraph('International Mobile, shared code ADD'),
                              paragraph('901 43 EMnify GmbH')))

      expect(parsed.actions.map { |action| [action.action_type, action.entries.map(&:mcc_mnc_codes)] })
        .to eq([['ADD', ['278 11']], ['ADD', ['901 43']]])
      expect(parsed.actions.first.entries.first.country_or_area.en).to eq('Malta')
      expect(parsed.actions.first.entries.first.networks).to eq('YOM')
      expect(parsed.actions.last.entries.first.country_or_area.en).to eq('International Mobile, shared code')
    end

    it 'preserves non-breaking spaces within an inline network name' do
      network = "YOM\u00a0Wireless"
      parsed = described_class.inline_country_entry("Malta ADD 278 11 #{network}")

      expect(parsed[:network]).to eq(network)
    end

    it 'retains the North America MNC formatting note without inventing an entry (OB 1007)' do
      note = 'For North America three digits MNC have been assigned with MNC with a trailing 0'
      parsed = parse(document(paragraph('Canada ADD'), paragraph('302 220 Telus Mobility'), paragraph(note)))

      expect(parsed.notes).to include(note)
      expect(parsed.actions.flat_map(&:entries).map(&:mcc_mnc_codes)).to eq(['302 220'])
    end

    it 'retains heading annotations in the action position without changing the table values' do
      headings = [
        'P 17 International Mobile, shared code 901 13 (Global Networks Switzerland AG) LIR',
        'P 7 Canada (http://www.cnac.ca/other_codes/imsi/imsi_codes.htm) REP all information by',
        'P 40 Switzerland ADD (extra-territorial use of MCC/MNC, Annex E to ITU-T Recommendation E.212)',
        'P 9 Georgia LIR'
      ]
      headings.each do |heading|
        parsed = parse(document(paragraph(heading),
                                table(header, row(cell(paragraph('Printed country')), cell(paragraph('228 01')),
                                                  cell(paragraph('Operator'))))))

        expect(parsed.actions.first.position).to eq(heading)
        expect(parsed.actions.first.entries.first.mcc_mnc_codes).to eq('228 01')
        expect(parsed.actions.first.entries.first.country_or_area.en).to eq('Printed country')
      end
    end

    it 'applies star-keyed effective dates and preserves ordinary entries' do
      doc = document(paragraph('P 1 Denmark ADD*'),
                     table(header, row(cell(paragraph('Denmark')), cell(paragraph('238 01')), cell(paragraph('Operator')))),
                     paragraph('* As from 1 June 2024'))
      entry = parse(doc).actions.first.entries.first

      expect(entry.effective_date).to eq('1 June 2024')
      expect(entry.note.en).to eq('* As from 1 June 2024')
      expect(entry.extra_territorial_use).to be_nil
    end

    it 'retains a keyed country note without applying it to unrelated countries (OB 1280)' do
      note = '* This designation is without prejudice to positions on status.'
      doc = document(table(header, row(cell(paragraph('Kosovo* SUP')), cell(paragraph('')), cell(paragraph(''))), row(cell(paragraph('221 06')), cell(paragraph('Dardafon.Net LLC'))),
                           row(cell(paragraph('New Zealand ADD')), cell(paragraph('')), cell(paragraph(''))), row(cell(paragraph('530 11')), cell(paragraph('Interim Māori Spectrum Commission')))),
                     paragraph(note))
      parsed = parse(doc)
      entries = parsed.actions.flat_map(&:entries)

      expect(parsed.notes).to include(note)
      expect(entries.first.note.en).to eq(note)
      expect(entries.last.note).to be_nil
      expect(entries.map(&:mcc_mnc_codes)).to eq(['221 06', '530 11'])
    end

    it 'retains keyed table note rows and their prose continuations (OB 1102)' do
      note = '** MCC+MNC "248 05" was assigned to AS Bravocom Mobiil until 19 April 2007.'
      continued = 'Then it was assigned to Skycompiler OÜ on 15 March 2011.'
      doc = document(table(header,
                           row(cell(paragraph('Estonia')), cell(paragraph('248 05')), cell(paragraph('Skycompiler OÜ**'))),
                           row(cell(paragraph(note)), cell(paragraph('')), cell(paragraph('')))),
                     paragraph('    ' + continued))
      parsed = parse(doc)
      entries = parsed.actions.flat_map(&:entries)

      expect(entries.map(&:mcc_mnc_codes)).to eq(['248 05'])
      expect(entries.first.note.en).to eq(note + "\n" + continued)
      expect(parsed.notes).to include(note + "\n" + continued)
    end

    it 'retains the destination country and marks a code-first extra-territorial row (OB 1016)' do
      doc = document(paragraph('Switzerland ADD (extra-territorial use of MCC/MNC, Annex E to ITU-T Recommendation E.212)'),
                     table(row(cell(paragraph('MCC/MNC')), cell(paragraph('Operator')), cell(paragraph('Country B')),
                               cell(paragraph('Country A range')), cell(paragraph('Country B range'))),
                           row(cell(paragraph('228 01')), cell(paragraph('Swisscom')), cell(paragraph('Principality of Liechtenstein')),
                               cell(paragraph('20XXXXXXXX (Switzerland)')), cell(paragraph('37XXXXXXXX (Liechtenstein)')))))
      action = parse(doc).actions.first
      entry = action.entries.first

      expect(action.action_type).to eq('ADD')
      expect(entry.extra_territorial_use).to be(true)
      expect(entry.country_or_area.en).to eq('Switzerland')
      expect(entry.note.en).to include('Principality of Liechtenstein')
      expect(entry.range).to eq('20XXXXXXXX (Switzerland) 37XXXXXXXX (Liechtenstein)')
      expect(entry.mcc_mnc_codes).to eq('228 01')
    end

    it 'preserves footnotes and extra-territorial details in the real bulletins' do
      parsed = [989, 1008, 1102, 1280, 1304, 1016].to_h do |issue|
        path = File.expand_path("../../../../itu-ob-data/issues/#{issue}/amendments.yaml", __dir__)
        data = YAML.load_file(path, permitted_classes: [Date, Time])
        message = data['messages'].find { |m| m['target']['publication'] == 'E212_MNC' }
        [issue, parse(message['contents']['en'])]
      end
      first = parsed[989].actions.flat_map(&:entries)
      second = parsed[1008].actions.flat_map(&:entries)
      estonia = parsed[1102].actions.flat_map(&:entries).find { |entry| entry.networks.include?('**') }
      kosovo = parsed[1280].actions.flat_map(&:entries).find { |entry| entry.country_or_area.en.start_with?('Kosovo') }
      trial = parsed[1304].actions.flat_map(&:entries).find { |entry| entry.mcc_mnc_codes == '991 04' }
      switzerland = parsed[1016].actions.flat_map(&:entries).find { |entry| entry.mcc_mnc_codes == '228 01' }

      expect(first.find { |entry| entry.mcc_mnc_codes == '901 33' }.effective_date).to eq('31 August 2011')
      expect(first.reject { |entry| entry.mcc_mnc_codes == '901 33' }.map(&:effective_date)).to all(be_nil)
      expect(second.first.effective_date).to eq('15 June 2012')
      expect(estonia.note.en).to include('19 April 2007', '15 March 2011', '15 March 2013')
      expect(kosovo.note.en).to include('UNSCR 1244')
      expect(trial.note.en).to include('18.X.2024')
      expect(switzerland.extra_territorial_use).to be(true)
      expect(switzerland.note.en).to include('Principality of Liechtenstein')
    end

    it 'marks an unmatched Country B row while preserving its country and qualifier' do
      doc = document(table(row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')),
                               cell(paragraph('MSIN range')), cell(paragraph('Operator'))),
                           row(cell(paragraph('Sweden (Country B – extra-territorial)')), cell(paragraph('262 74')),
                               cell(paragraph('1 - 2')), cell(paragraph('Ericsson')))))
      entry = parse(doc).actions.first.entries.first

      expect(entry.extra_territorial_use).to be(true)
      expect(entry.note.en).to eq('(Country B – extra-territorial)')
      expect(entry.country_or_area.en).to eq('Sweden')
    end
  end

  describe 'E.212 baseline seed' do
    let(:seed) do
      path = File.expand_path('../../../../datasets/1162-E.212/data.yaml', __dir__)
      YAML.load_file(path)
    end

    it 'holds one entry per MCC+MNC for the France/Monaco extra-territorial codes' do
      {
        '208 01' => ['Orange', 'Orange/Monaco Télécom'],
        '208 10' => ['Société Française du Radiotéléphone', 'Société Française du Radiotéléphone'],
        '208 20' => ['Bouygues Telecom', 'Bouygues Telecom']
      }.each do |code, (home_network, away_network)|
        rows = seed.select { |row| row['mcc_mnc_codes'] == code }

        expect(rows.map { |row| row['country_or_area']['en'] }).to eq(['France'])
        expect(rows.first['networks']).to eq(home_network)
        expect(rows.first['note']['en']).to eq("Extra-territorial use in Monaco: #{away_network}")
        expect(rows.first['note'].keys).to eq(%w[en fr es ru zh ar])
      end
    end

    it 'preserves every Indian Ocean code and operator printed in OB 1162 page 18' do
      rows = seed.select { |entry| entry['mcc_mnc_codes'].start_with?('647 ') }

      expect(rows.map { |entry| entry['country_or_area']['en'] }.uniq)
        .to eq(['French Departments and Territories in the Indian Ocean'])
      expect(rows.map { |entry| [entry['mcc_mnc_codes'], entry['networks']] }).to eq([
        ['647 00', 'Orange'],
        ['647 01', 'BJT Partners'],
        ['647 02', 'Telco OI'],
        ['647 03', 'Telco OI'],
        ['647 04', 'Zeop Mobile'],
        ['647 10', 'Société Réunionnaise du Radiotéléphone']
      ])
    end

    it 'has no duplicate MCC+MNC key' do
      duplicates = seed.group_by { |row| row['mcc_mnc_codes'] }
                       .select { |_code, rows| rows.size > 1 }
                       .transform_values { |rows| rows.map { |row| row['country_or_area']['en'] } }

      expect(duplicates).to eq({})
    end

    it 'keeps the owning country and notes the extra-territorial one (OB 1162 Country A / B)' do
      {
        '270 77' => %w[Luxembourg Belgium],
        '274 02' => ['Iceland', 'Faroe Islands'],
        '542 02' => %w[Fiji Nauru],
        '228 01' => %w[Switzerland Liechtenstein]
      }.each do |code, (owner, extra)|
        row = seed.find { |entry| entry['mcc_mnc_codes'] == code }

        expect(row['country_or_area']['en']).to eq(owner)
        expect(row['note']['en']).to start_with("Extra-territorial use in #{extra}")
        expect(row['note'].keys).to eq(%w[en fr es ru zh ar])
      end
    end
  end

  context 'follow-up regressions' do
    let(:header) do
      row(cell(paragraph('Country')), cell(paragraph('MCC+MNC')),
          cell(paragraph('Range')), cell(paragraph('Network')))
    end
    let(:home) do
      row(cell(paragraph('France (Country A)')), cell(paragraph('208 01')),
          cell(paragraph('A')), cell(paragraph('Home')))
    end
    let(:abroad) do
      row(cell(paragraph('Monaco (Country B – x)')), cell(paragraph('208 01')),
          cell(paragraph('B')), cell(paragraph('S.A..')))
    end

    it 'skips headers by content regardless of case spacing or first row' do
      repeated = row(cell(paragraph('COUNTRY OR GEOGRAPHICAL AREA')), cell(paragraph(' mcc + mnc * ')),
                     cell(paragraph('MSIN** range to be used')), cell(paragraph('Operators Name')))
      entries = parse(document(table(row(cell(paragraph(''))), header, home, repeated))).actions.flat_map(&:entries)
      expect(entries.map(&:mcc_mnc_codes)).to eq(['208 01'])
      [1094, 1108].each do |issue|
        path = File.expand_path("../../../../itu-ob-data/issues/#{issue}/amendments.yaml", __dir__)
        data = YAML.load_file(path, permitted_classes: [Date, Time])
        msg = data['messages'].find { |m| m['target']['publication'] == 'E212_MNC' }
        codes = parse(msg['contents']['en']).actions.flat_map(&:entries).map(&:mcc_mnc_codes)
        expect(codes).to all(match(/\A\d{3} \d{2,3}\z/))
      end
    end

    it 'cleans Country A markers punctuation and empty Country B details' do
      empty = row(cell(paragraph('Andorra (Country B – y)')), cell(paragraph('208 01')),
                  cell(paragraph('')), cell(paragraph('')))
      entry = parse(document(table(header, home, abroad, empty))).actions.flat_map(&:entries).first
      expect(entry.note.en).to eq("Extra-territorial use in Monaco (Country B – x): S.A.; MSIN range B\n" \
                                'Extra-territorial use in Andorra (Country B – y)')
    end

    it 'updates country carry-over before skipping a blank code' do
      spain = row(cell(paragraph('Spain')), cell(paragraph('')), cell(paragraph('')), cell(paragraph('')))
      carried = row(cell(paragraph('')), cell(paragraph('214 01')), cell(paragraph('')), cell(paragraph('Vodafone')))
      entries = parse(document(table(header, home, spain, carried))).actions.flat_map(&:entries)
      expect(entries.map { |e| [e.mcc_mnc_codes, e.country_or_area.en] })
        .to eq([['208 01', 'France'], ['214 01', 'Spain']])
    end

    it 'never treats a qualifier-only cell as a country' do
      odd = row(cell(paragraph('(Country B – x)')), cell(paragraph('208 02')),
                cell(paragraph('B')), cell(paragraph('Other')))
      entry = parse(document(table(header, home, odd))).actions.flat_map(&:entries).last
      expect(entry.country_or_area.en).to eq('France')
      expect(entry.note.en).to eq('(Country B – x)')
    end

    it 'pairs Country B before Country A without a duplicate allocation' do
      entries = parse(document(table(header, abroad, home))).actions.flat_map(&:entries)
      expect(entries.size).to eq(1)
      expect(entries.first.country_or_area.en).to eq('France')
      expect(entries.first.note.en).to eq('Extra-territorial use in Monaco (Country B – x): S.A.; MSIN range B')
    end

    it 'opens a LIR for a generic extra-territorial heading after an ADD (OB 1296)' do
      path = File.expand_path('../../../../itu-ob-data/issues/1296/amendments.yaml', __dir__)
      data = YAML.load_file(path, permitted_classes: [Date, Time])
      msg = data['messages'].find { |m| m['target']['publication'] == 'E212_MNC' }
      actions = parse(msg['contents']['en']).actions
      expect(actions.map { |a| [a.action_type, a.entries.map(&:mcc_mnc_codes)] })
        .to eq([['ADD', ['228 73']], ['LIR', ['270 07']]])
    end

    it 'pairs large Country B blocks within a linear work budget' do
      homes = 8000.times.map do |n|
        row(cell(paragraph('France (Country A)')), cell(paragraph("208 #{n}")),
            cell(paragraph('A')), cell(paragraph('Home')))
      end
      uses = 8000.times.map do |n|
        row(cell(paragraph('Monaco (Country B – x)')), cell(paragraph("208 #{n}")),
            cell(paragraph('B')), cell(paragraph('Away')))
      end
      entries = Timeout.timeout(8) { parse(document(table(header, *homes, *uses))).actions.flat_map(&:entries) }
      expect(entries.size).to eq(8000)
      expect(entries.map { |e| e.note.en }).to all(include('Extra-territorial use in Monaco'))
    end
  end
end
