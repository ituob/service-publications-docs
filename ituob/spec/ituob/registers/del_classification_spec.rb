# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'
require 'ituob/registers'

RSpec.describe 'Printed deletion classification' do
  context 'with the printed Sweden DEL table in OB 1335' do
    let(:document) do
      bulletin = Ituob::Support::Yaml.safe_load_file(File.join(FIXTURE_ROOT, '1335/amendments.yaml'))
      bulletin.fetch('messages').find do |message|
        message.dig('target', 'publication') == 'Q708_ISPC'
      end.fetch('contents').fetch('en')
    end
    let(:amendment) { Ituob::Models::Q708ISPCAmendment.parse(document) }

    # Source: amendments.yaml:495, followed by three Tele2 Sverige AB rows.
    # Keep the preceding Spain ADD: the deletion must open a new action.
    it 'classifies the printed deletion separately from the preceding ADD' do
      expect(amendment.actions.map(&:action_type)).to eq(%w[ADD DEL])
      expect(amendment.actions.first.entries.map(&:ipsc)).to eq(['2-027-4'])
      deletion = amendment.actions.last
      expect(deletion.entries.map(&:ipsc)).to eq(%w[2-080-2 2-080-3 2-081-6])
      expect(deletion.entries.map { |entry| entry.country.en }.uniq).to eq(['Sweden'])
    end
  end

  context 'with the printed Norway SUP (delete) in OB 999' do
    let(:document) do
      bulletin = Ituob::Support::Yaml.safe_load_file(File.join(FIXTURE_ROOT, '999/amendments.yaml'))
      bulletin.fetch('messages').find do |message|
        message.dig('target', 'publication') == 'E212_MNC'
      end.fetch('contents').fetch('en')
    end

    # Source: amendments.yaml:939. The explanatory word does not rename SUP.
    it 'preserves SUP for the printed deletion of a mobile network code' do
      amendment = Ituob::Models::E212MNCAmendment.parse(document)
      action = amendment.actions.find do |candidate|
        candidate.entries.any? do |entry|
          entry.mcc_mnc_codes == '242 09' && entry.networks == 'Mundio Mobile Norway Ltd'
        end
      end
      expect(action).not_to be_nil
      expect(action.action_type).to eq('SUP')
    end
  end

  it 'replays a DEL patch into deleted_keys without removing another key' do
    changes = [
      Ituob::Registers::Change.new(
        type: 'SEED', register_id: 'Q708_ISPC', ob_issue_no: 1334,
        identifier: { 'code' => '__seed__' },
        data: [{ 'ipsc' => '2-080-2' }, { 'ipsc' => '2-027-4' }],
      ),
      Ituob::Registers::Change.from_hash(
        'type' => 'DEL', 'register' => 'Q708_ISPC', 'ob_issue_no' => '1335',
        'identifier' => { 'code' => '1335-002' },
        'data' => { 'entries' => [{ 'ipsc' => '2-080-2' }] },
      ),
    ]
    source = Ituob::Registers::InlineChangeSource.new(register_id: 'Q708_ISPC', changes: changes)
    replay = Ituob::Registers::Replay.new(register_id: 'Q708_ISPC', key_field: 'ipsc', source: source)

    expect(replay.at_seed.active_keys).to contain_exactly('2-080-2', '2-027-4')
    state = replay.current
    expect(state.active_keys).to eq(['2-027-4'])
    expect(state.deleted_keys).to contain_exactly('2-080-2')
    expect(state.lapsed_keys).to be_empty
    expect(state.history.map(&:type)).to eq(%w[SEED DEL])
  end
end
