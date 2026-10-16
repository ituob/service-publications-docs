# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'
require 'yaml'

# Behavioral specs for the parsers whose output did not change in the
# 2026-08 parity campaign (those parsers have dedicated spec files).
# Each example parses a REAL source amendment from itu-ob-data and
# pins concrete parsed facts — characterization against the corpus the
# equivalence verifier gates.
RSpec.describe 'Registered amendment parsers (behavior)' do
  SOURCE_ROOT = File.expand_path('../../../../itu-ob-data/issues', __dir__)
  REGISTRY = Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS

  def load_source(pub_id, issue)
    data = YAML.load_file(
      File.join(SOURCE_ROOT, issue.to_s, 'amendments.yaml'),
      permitted_classes: [Date, Time],
    )
    msg = (data['messages'] || []).find do |m|
      m.is_a?(Hash) && m['target'].is_a?(Hash) && m['target']['publication'] == pub_id
    end
    msg && msg['contents']['en']
  end

  def parse(pub_id, issue)
    contents = load_source(pub_id, issue)
    raise "no #{pub_id} source in issue #{issue}" unless contents

    REGISTRY[pub_id].parse(contents)
  end

  it 'E164CC parses OB 989 country-code actions' do
    parsed = parse('E164_CC', 989)
    action = parsed.actions.first

    expect(parsed.actions.length).to eq(3)
    expect(action.action_type).to eq('SUP*')
    expect(action.position).to eq('P 17')
    entry = action.entries.first
    expect(entry.applicant).to eq('ICO Global Communications')
    expect(entry.cc_ic).to eq('+881 0 and +881 1')
    expect(entry.status).to eq('Withdrawn')
  end

  it 'Q708SANC parses OB 983 signalling-area codes' do
    parsed = parse('Q708_SANC', 983)
    action = parsed.actions.first

    expect(parsed.actions.length).to eq(2)
    expect(action.action_type).to eq('ADD')
    expect(action.position).to eq('P 13')
    entry = action.entries.first
    expect(entry.code).to eq('4-057')
    expect(entry.area_or_network.en).to eq('Nepal (Federal Democratic Republic of)')
  end

  it 'E218TRCC parses OB 1190 trunk-code assignments' do
    parsed = parse('E218_TRCC', 1190)
    action = parsed.actions.first

    expect(parsed.actions.length).to eq(1)
    expect(action.action_type).to eq('ADD')
    entry = action.entries.first
    expect(entry.tmcc_code).to eq('944 0002')
    expect(entry.country_or_area.en).to eq('Vattenfall Vindkraft A/S')
  end

  it 'T35NA parses OB 1000 assignment authorities' do
    parsed = parse('T35_NA', 1000)
    action = parsed.actions.first

    expect(parsed.actions.length).to eq(1)
    expect(action.action_type).to eq('ADD')
    expect(action.position).to eq('P 7')
    entry = action.entries.first
    expect(entry.country).to eq('Norway')
    expect(entry.administration_name).to eq('Norwegian Post and Telecommunications Authority')
  end

  it 'F400 parses OB 989 administration contacts' do
    parsed = parse('F400_ADMD', 989)
    action = parsed.actions.first

    expect(parsed.actions.length).to eq(1)
    expect(action.action_type).to eq('ADD')
    expect(action.position).to eq('P 8')
    seeburger = action.entries.last
    expect(seeburger.admd_name).to eq('SEEBURGER')
    expect(seeburger.country_code).to eq('DE')
    expect(seeburger.contact_address[:address_lines].join(' ')).to include('+49 7252 962222')
  end

  it 'M1400 parses OB 1137 company entries with contacts' do
    parsed = parse('M1400_ICC', 1137)
    action = parsed.actions.first

    expect(parsed.actions.length).to eq(8)
    expect(action.action_type).to eq('ADD')
    entry = action.entries.first
    expect(entry.country_or_area.en).to eq('Germany')
    expect(entry.company_name).to eq('BGC Breitbandgesellschaft Cottbus mbH')
    with_tel = parsed.actions.flat_map(&:entries).find { |e| e.tel.to_s.include?('104211') }
    expect(with_tel).not_to be_nil
  end

  it 'E118 parses OB 1125 IIN assignments' do
    parsed = parse('E118_IIN', 1125)
    action = parsed.actions.first

    expect(parsed.actions.length).to eq(1)
    expect(action.action_type).to eq('ADD')
    entry = action.entries.first
    expect(entry.country_or_area.en).to eq('Switzerland')
    expect(entry.company_name).to eq('Telecom26 AG')
  end

  it 'E164ACN parses OB 1003 country-code notices' do
    parsed = parse('E164_ACN', 1003)
    action = parsed.actions.first

    expect(parsed.actions.length).to eq(3)
    expect(action.action_type).to eq('LIR')
    expect(action.position).to eq('4')
    entry = action.entries.first
    expect(entry.country_or_area.en).to eq('Burkina Faso')
    expect(entry.country_code).to eq('226')
  end

  it 'DP parses numbering-plan entries (TODO.complete/51 rewrite)' do
    parsed = parse('DP', 983)
    action = parsed.actions.first
    entry = action.entries.first

    expect(action.action_type).to eq('LIR')
    expect(action.position).to eq('P 4')
    expect(entry.country_or_area.en).to eq('Dem. People’s Rep. of Korea')
    expect(entry.country_code).to eq('850')
    expect(entry.national_sig_number).to eq('6 to 17 digits')
  end
end
