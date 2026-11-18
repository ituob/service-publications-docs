# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'
require 'yaml'
require 'date'

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

  it 'retains the note letter and full printed marker for a network row' do
    doc = { 'type' => 'doc', 'content' => [
      paragraph('q     Associated with shared country code 883, four-digit assignments.'),
      paragraph('P 18   Note q)   +883 5110   ADD*'),
      table(%w[Applicant Network Code Status], ['Bandwith.com Inc', 'Bandwith.com Inc', '+883 5110', 'Assigned']),
    ] }
    amendment = described_class.parse(doc)
    action = amendment.actions.first
    expect(action.position).to eq('P 18 Note q) +883 5110 ADD*')
    expect(action.entries.first.notes).to include('q', 'q Associated with shared country code 883, four-digit assignments.')
    expect(action.entries.first.cc_ic).to eq('+883 5110')
    expect(action.action_type).to eq('ADD')
  end

  it 'keeps shared country code rows and their keyed definitions' do
    doc = { 'type' => 'doc', 'content' => [
      paragraph('country code     888     LIR'),
      table(['Country Code', 'Country, geographical area or global service', 'Note'],
            ['888', 'Humanitarian purposes', 'k, t']),
      paragraph('k     United Nations Office of the Coordinator for Humanitarian Affairs (OCHA)'),
      paragraph('t     Reserved pending further studies.'),
    ] }
    amendment = described_class.parse(doc)
    entry = amendment.actions.first.entries.first
    expect(entry.country_code).to eq('888')
    expect(entry.country_area_or_service.en).to eq('Humanitarian purposes')
    expect(entry.notes).to eq(['k', 't',
                             'k United Nations Office of the Coordinator for Humanitarian Affairs (OCHA)',
                             't Reserved pending further studies.'])
    expect(amendment.notes).to include('t Reserved pending further studies.')
    expect(amendment.actions.first.action_type).to eq('LIR')
  end

  ['* As from 19 September 2014', '* 19 September 2014'].each do |footnote|
    it "attaches #{footnote.inspect} only to the preceding starred table" do
      doc = { 'type' => 'doc', 'content' => [
        paragraph('Note p) +883 320 ADD*'),
        table(%w[Applicant Network Code Status], ['Tele2 (Formerly Old)', 'Tele2', '+883 320', 'Assigned']),
        paragraph(footnote),
        paragraph('Note q) +883 5110 SUP'),
        table(%w[Applicant Network Code Status], ['Bandwith.com Inc', 'Bandwith.com Inc', '+883 5110', 'Withdrawn']),
      ] }
      amendment = described_class.parse(doc)
      first, second = amendment.actions.select { |action| action.entries.any? }
      expect(first.entries.first.effective_date).to eq('19 September 2014')
      expect(first.entries.first.to_hash['effective_date']).to eq('19 September 2014')
      expect(second.entries.first.effective_date).to be_nil
      expect(first.entries.first.formerly).to eq('Old')
      expect(second.entries.first.status).to eq('Withdrawn')
      expect(amendment.notes).to include(footnote)
    end
  end


  { 984 => ['cc_ic', '+883 5110', 'q'],
    1062 => ['effective_date', '19 September 2014', 'p'],
    1186 => ['country_code', '888', 'k'],
    1225 => ['country_code', '997', 'f'] }.each do |issue, (field, value, note_key)|
    it "retains the printed E164_CC row and note key in issue #{issue}" do
      source = YAML.load_file(File.join(FIXTURE_ROOT, issue.to_s, 'amendments.yaml'),
                              permitted_classes: [Date, Time], aliases: true)
      message = source.fetch('messages').find { |item| item.dig('target', 'publication') == 'E164_CC' }
      amendment = described_class.parse(message.dig('contents', 'en'))
      entries = amendment.actions.flat_map(&:entries)
      entry = entries.find { |item| item.public_send(field) == value }
      expect(entry).not_to be_nil
      expect(entry.notes).to include(note_key)
      expect(entry.to_hash[field]).to eq(value)
    end
  end


  it 'retains the trial assignment columns and the s definition from issue 1190' do
    source = YAML.load_file(File.join(FIXTURE_ROOT, '1190', 'amendments.yaml'),
                            permitted_classes: [Date, Time], aliases: true)
    message = source.fetch('messages').find { |item| item.dig('target', 'publication') == 'E164_CC' }
    amendment = described_class.parse(message.dig('contents', 'en'))
    entry = amendment.actions.flat_map(&:entries).first
    expect(entry.cc_ic).to eq('+991 001')
    expect(entry.applicant).to eq('World’s Global Telecom')
    expect(entry.effective_date).to eq('15.I.2020')
    expect(entry.reclamation_date).to eq('15.I.2021')
    expect(entry.notes).to include('s', a_string_starting_with('s Associated with shared country code 991'))
  end

  it 'keeps repeated note definitions with their own table' do
    doc = { 'type' => 'doc', 'content' => [
      paragraph('p First definition.'), paragraph('Note p) +883 320 ADD'),
      table(%w[Applicant Network Code Status], ['Tele2', 'Tele2', '+883 320', 'Assigned']),
      paragraph('p Second definition.'), paragraph('Note p) +883 321 ADD'),
      table(%w[Applicant Network Code Status], ['Other', 'Other', '+883 321', 'Assigned']),
    ] }
    entries = described_class.parse(doc).actions.flat_map(&:entries)
    expect(entries[0].notes).to eq(['p', 'p First definition.'])
    expect(entries[1].notes).to eq(['p', 'p Second definition.'])
  end


  it 'keeps three-column network rows separate from country-code rows' do
    doc = { 'type' => 'doc', 'content' => [
      paragraph('n Network definition.'), paragraph('Note n) +881 6 ADD'),
      table(%w[Network Code Status], ['Iridium', '+881 6', 'Assigned']),
    ] }
    entry = described_class.parse(doc).actions.first.entries.first
    expect(entry.network).to eq('Iridium')
    expect(entry.cc_ic).to eq('+881 6')
    expect(entry.status).to eq('Assigned')
    expect(entry.country_code).to be_nil
    expect(entry.notes).to eq(['n', 'n Network definition.'])
  end


  it 'preserves the note suppression directive before a following country-code marker' do
    doc = { 'type' => 'doc', 'content' => [
      paragraph('SUP     note e'),
      paragraph('e Associated with shared country code 878 for Universal personal telecommunications.'),
      paragraph('country code     878     LIR'),
      table(['Country Code', 'Country, geographical area or global service', 'Note'],
            ['878', 'Universal Personal Telecommunication Service (UPT)', '']),
    ] }
    amendment = described_class.parse(doc)
    expect(amendment.notes).to include('SUP note e')
    expect(amendment.actions.first.action_type).to eq('LIR')
    expect(amendment.actions.first.entries.first.country_code).to eq('878')
  end


  it 'reads the issue 1052 table footnote as the assignment date, without creating another entry' do
    source = YAML.load_file(File.join(FIXTURE_ROOT, '1052', 'amendments.yaml'),
                            permitted_classes: [Date, Time], aliases: true)
    message = source.fetch('messages').find { |item| item.dig('target', 'publication') == 'E164_CC' }
    amendment = described_class.parse(message.dig('contents', 'en'))
    entries = amendment.actions.flat_map(&:entries)
    expect(entries.map(&:cc_ic)).to eq(['+883 5140'])
    expect(entries.first.applicant).to eq('Ellipsat Inc')
    expect(entries.first.effective_date).to eq('15 April 2014')
    expect(amendment.notes).to include('* 15 April 2014')
  end

  it 'recognizes table date footnotes and skips header rows instead of creating network entries' do
    doc = { 'type' => 'doc', 'content' => [
      paragraph('Note q) +883 5140 ADD*'),
      table(%w[Applicant Network Code Status], ['Ellipsat Inc', 'Ellipsat Inc', '+883 5140', 'Assigned'],
            ["\u00a0", '* As from 15 April 2014', "\u00a0"],
            %w[Network Code Status]),
    ] }
    amendment = described_class.parse(doc)
    entries = amendment.actions.flat_map(&:entries)
    expect(entries.map(&:cc_ic)).to eq(['+883 5140'])
    expect(entries.first.effective_date).to eq('15 April 2014')
    expect(amendment.notes).to include('* As from 15 April 2014')
  end

  { 1130 => ['+883 240', '25.VII.2017'],
    1114 => ['+883 5140', '15.IV.2014'],
    1126 => ['+883 230', '23.V.2017'] }.each do |issue, (code, date)|
    it "retains the Roman-numeral assignment date in issue #{issue}" do
      source = YAML.load_file(File.join(FIXTURE_ROOT, issue.to_s, 'amendments.yaml'),
                              permitted_classes: [Date, Time], aliases: true)
      message = source.fetch('messages').find { |item| item.dig('target', 'publication') == 'E164_CC' }
      amendment = described_class.parse(message.dig('contents', 'en'))
      matching = amendment.actions.flat_map(&:entries).select { |entry| entry.cc_ic == code }
      expect(matching).not_to be_empty
      expect(matching.map(&:effective_date)).to all(eq(date))
      expect(amendment.notes).to include("* #{date}")
    end
  end

  it 'preserves both printed dates in issue 1161 without assigning an ambiguous date to every row' do
    source = YAML.load_file(File.join(FIXTURE_ROOT, '1161', 'amendments.yaml'),
                            permitted_classes: [Date, Time], aliases: true)
    message = source.fetch('messages').find { |item| item.dig('target', 'publication') == 'E164_CC' }
    amendment = described_class.parse(message.dig('contents', 'en'))
    entries = amendment.actions.flat_map(&:entries)
    expect(amendment.notes).to include('* 2.XI.2018; 20.XI.2018')
    expect(entries.map(&:cc_ic)).to eq(['+883 260', '+883 270', '+991 001'])
    expect(entries.first(2).map(&:effective_date)).to eq([nil, nil])
    expect(entries.last.effective_date).to eq('15.I.2019')
    expect(entries.last.reclamation_date).to eq('15.I.2020')
  end

  it 'applies the shared date to both starred withdrawals in issue 1091' do
    source = YAML.load_file(File.join(FIXTURE_ROOT, '1091', 'amendments.yaml'),
                            permitted_classes: [Date, Time], aliases: true)
    message = source.fetch('messages').find { |item| item.dig('target', 'publication') == 'E164_CC' }
    amendment = described_class.parse(message.dig('contents', 'en'))
    entries = amendment.actions.flat_map(&:entries)
    expect(entries.map(&:cc_ic)).to eq(['+882 20', '+883 5140'])
    expect(entries.map(&:effective_date)).to eq(['15 December 2015', '15 December 2015'])
    expect(entries.map(&:status)).to eq(['Withdrawn', 'Withdrawn'])
  end

  it 'keeps date markers within their block and leaves unstarred rows unchanged' do
    doc = { 'type' => 'doc', 'content' => [
      paragraph('Note p) +883 320 ADD*'),
      table(%w[Applicant Network Code Status], ['First', 'First', '+883 320', 'Assigned']),
      paragraph('Notes common to Numerical and Alphabetical lists'),
      paragraph('Note p) +883 321 ADD**'),
      table(%w[Applicant Network Code Status], ['Second', 'Second', '+883 321', 'Assigned']),
      paragraph('* 25.VII.2017'),
      paragraph('** 26.VII.2017'),
      paragraph('Note p) +883 322 ADD'),
      table(%w[Applicant Network Code Status], ['Third', 'Third', '+883 322', 'Assigned']),
      paragraph('* 27.VII.2017'),
    ] }
    amendment = described_class.parse(doc)
    entries = amendment.actions.flat_map(&:entries)
    expect(entries.map(&:effective_date)).to eq([nil, '26.VII.2017', nil])
    expect(entries.map(&:cc_ic)).to eq(['+883 320', '+883 321', '+883 322'])
    expect(amendment.notes).to include('* 25.VII.2017', '** 26.VII.2017', '* 27.VII.2017')
  end

  it 'binds issue 1240 dates to the codes in each consecutive starred heading' do
    source = YAML.load_file(File.join(FIXTURE_ROOT, '1240', 'amendments.yaml'),
                            permitted_classes: [Date, Time], aliases: true)
    message = source.fetch('messages').find { |item| item.dig('target', 'publication') == 'E164_CC' }
    amendment = described_class.parse(message.dig('contents', 'en'))
    actions = amendment.actions.select { |action| action.entries.any? }
    entries = actions.flat_map(&:entries)
    dates = entries.to_h { |entry| [entry.cc_ic, entry.effective_date] }
    expect(dates).to eq('+882 12' => '4.III.2022', '+882 22' => '4.III.2022',
                        '+882 33' => '18.II.2022', '+882 97' => '4.III.2022',
                        '+883 120' => '4.III.2022', '+883 180' => '18.II.2022',
                        '+883 230' => '18.II.2022', '+883 310' => '18.II.2022',
                        '+883 430' => '18.II.2022')
    expect(actions.map(&:position)).to eq(['Note o) +882 12, +882 22, +882 97 SUP**',
                                          'Note p) +883 120 SUP**',
                                          'Note p) +883 430 ADD***'])
    expect(actions.map { |action| action.entries.map(&:cc_ic) }).to eq([
      ['+882 12', '+882 22', '+882 33', '+882 97'],
      ['+883 120', '+883 180', '+883 230', '+883 310'], ['+883 430'],
    ])
    expect(actions.select { |action| action.action_type == 'SUP' }.flat_map(&:entries).map(&:status)).to all(eq('Withdrawn'))
    expect(actions.select { |action| action.action_type == 'ADD' }.flat_map(&:entries).map(&:cc_ic)).to eq(['+883 430'])
    expect(entries.find { |entry| entry.cc_ic == '+883 430' }.status).to eq('Assigned')
    expect(amendment.notes).to include('* 18.II.2022', '** 4.III.2022', '*** 18.II.2022')
  end

end
