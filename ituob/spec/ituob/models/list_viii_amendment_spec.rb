# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'
require 'yaml'

RSpec.describe Ituob::Models::ListVIIIAmendment do
  SOURCE_ROOT = File.expand_path('../../../../itu-ob-data/issues', __dir__)

  def load_source(issue)
    data = YAML.load_file(
      File.join(SOURCE_ROOT, issue.to_s, 'amendments.yaml'),
      permitted_classes: [Date, Time],
    )
    msg = data['messages'].find { |m| m['target']['publication'] == 'R_SP_LN.VIII' }
    msg && msg['contents']['en']
  end

  def parse_issue(issue)
    described_class.parse(load_source(issue))
  end

  it 'parses the compact monitoring block (OB 1044)' do
    parsed = parse_issue(1044)
    action = parsed.actions.first
    station = action.entries.first

    expect(action.action_type).to eq('ADD')
    expect(action.position).to eq('P 330')
    expect(station.name).to eq('Yakutsk')
    expect(station.postal_address).to start_with('17, Irtyshskiy proezd')
    expect(station.centralizing_office.name).to start_with('Federal State Unitary Enterprise')
    expect(station.measurements.length).to be >= 5
    first = station.measurements.first
    expect(first.measurement_type).to eq('Frequency measurements')
    expect(first.coordinates).to include("61°54'41''N")
    expect(first.hours_of_service).to eq('H24')
    expect(first.frequency_ranges).to include('10 kHz')
  end

  it 'parses the full-part republication (OB 1002)' do
    parsed = parse_issue(1002)

    expect(parsed.actions.length).to eq(2)
    index_action, section_action = parsed.actions
    expect(index_action.action_type).to eq('ADD')
    expect(index_action.position).to eq('P 43')
    slavyanka = index_action.entries.first
    expect(slavyanka.name).to start_with('Slavyanka')
    expect(slavyanka.country).to eq('RUS Russian Federation')
    expect(slavyanka.postal_address).to start_with('17, Irtyshskiy proezd')

    expect(section_action.action_type).to eq('REP')
    named = section_action.entries.find { |s| s.name.to_s.start_with?('Arkhangelsk') }
    expect(named).not_to be_nil
    freq = named.measurements.find { |m| m.section == 'A' }
    expect(freq.measurement_type).to include('Frequency measurements')
    expect(freq.frequency_ranges).to include('9 kHz')
  end

  it 'parses index-only announcements with MARS profiles (OB 1133)' do
    parsed = parse_issue(1133)
    names = parsed.actions.flat_map(&:entries).map(&:name)

    expect(names).to include('Chengdu', 'Shanxi')
  end

  it 'keeps printed header, section, and footnote wording as notes' do
    notes = parse_issue(1002).notes.join("\n")

    expect(notes).to include('Nom de la station')
    expect(notes).to include('Section A')
    expect(notes).to include('active antenna')
  end

  it 'ends-on-office amendments still produce a station (OB 1076)' do
    parsed = parse_issue(1076)
    station = parsed.actions.flat_map(&:entries).first

    expect(station.centralizing_office.name).to start_with('Wireless Adviser')
  end

  it 'parses the whole corpus without errors and with entries' do
    issues = 0
    Dir.glob(File.join(SOURCE_ROOT, '*', 'amendments.yaml')).sort.each do |path|
      data = YAML.load_file(path, permitted_classes: [Date, Time])
      msg = (data['messages'] || []).find { |m| m['target']['publication'] == 'R_SP_LN.VIII' rescue false }
      next unless msg && msg['contents']['en']

      issues += 1
      parsed = described_class.parse(msg['contents']['en'])
      expect(parsed.actions.flat_map(&:entries)).not_to be_empty, "no entries in #{path}"
    end
    expect(issues).to eq(30)
  end
end
