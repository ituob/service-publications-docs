# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'ituob/registers'

RSpec.describe Ituob::Registers::Replay do
  let(:seed_dir) { Dir.mktmpdir('replay-spec') }
  let(:changes_dir) { File.join(seed_dir, 'changes') }

  before do
    FileUtils.mkdir_p(changes_dir)
    File.write(File.join(seed_dir, 'data.yaml'), [
      { 'code' => 'ABC', 'field' => 'accounts', 'message' => { 'en' => 'first' } },
      { 'code' => 'DEF', 'field' => 'addresses', 'message' => { 'en' => 'second' } },
    ].to_yaml)
  end

  after { FileUtils.rm_rf(seed_dir) }

  def write_change(filename, hash)
    File.write(File.join(changes_dir, filename), hash.merge('register' => 'F1').to_yaml)
  end

  let(:source) do
    Ituob::Registers::DirectoryChangeSource.new(
      register_id: 'F1',
      seed_path: seed_dir,
      seed_issue: 669,
      key_field: 'code',
    )
  end

  let(:replay) { described_class.new(register_id: 'F1', key_field: 'code', source: source) }

  describe '#at_issue' do
    it 'returns seed-only state at the seed issue' do
      s = replay.at_issue(669)
      expect(s.entry_count).to eq(2)
      expect(s.active_keys.sort).to eq(%w[ABC DEF])
    end

    it 'returns empty state before the seed' do
      s = replay.at_issue(600)
      expect(s.entry_count).to eq(0)
    end

    it 'applies an ADD after the seed' do
      write_change('700-001-ADD-GHI.yaml', {
        'type' => 'ADD', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'GHI' },
        'data' => { 'field' => 'delivery', 'message' => { 'en' => 'third' } },
      })
      s = replay.at_issue(700)
      expect(s.active_keys.sort).to eq(%w[ABC DEF GHI])
    end

    it 'honours the cutoff (later changes excluded)' do
      write_change('700-001-ADD-GHI.yaml', {
        'type' => 'ADD', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'GHI' },
        'data' => { 'field' => 'delivery' },
      })
      write_change('800-001-ADD-JKL.yaml', {
        'type' => 'ADD', 'ob_issue_no' => '800',
        'identifier' => { 'code' => 'JKL' },
        'data' => { 'field' => 'delivery' },
      })
      s = replay.at_issue(700)
      expect(s.active_keys).to contain_exactly('ABC', 'DEF', 'GHI')
    end

    it 'applies LIR (entry remains but excluded from active)' do
      write_change('700-001-LIR-ABC.yaml', {
        'type' => 'LIR', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'ABC' },
        'reason' => { 'en' => 'Deprecated' },
      })
      s = replay.at_issue(700)
      expect(s.active_keys).to eq(['DEF'])
      expect(s.lapsed_keys).to include('ABC')
      expect(s.entry_for('ABC')['field']).to eq('accounts')
    end

    it 'applies MOD (merge)' do
      write_change('700-001-MOD-DEF.yaml', {
        'type' => 'MOD', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'DEF' },
        'data' => { 'message' => { 'en' => 'second (updated)' } },
      })
      s = replay.at_issue(700)
      expect(s.entry_for('DEF')['field']).to eq('addresses')
      expect(s.entry_for('DEF')['message']['en']).to eq('second (updated)')
    end

    it 'applies SUP (hard delete + supersession)' do
      write_change('700-001-SUP-ABC.yaml', {
        'type' => 'SUP', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'ABC' },
        'superseded_by' => { 'identifier' => { 'code' => 'DEF' } },
      })
      s = replay.at_issue(700)
      expect(s.active_keys).to eq(['DEF'])
      expect(s.deleted_keys).to include('ABC')
    end

    it 'applies DEL (hard delete)' do
      write_change('700-001-DEL-ABC.yaml', {
        'type' => 'DEL', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'ABC' },
      })
      s = replay.at_issue(700)
      expect(s.active_keys).to eq(['DEF'])
      expect(s.deleted_keys).to include('ABC')
    end

    it 'records history in order' do
      write_change('700-001-ADD-GHI.yaml', {
        'type' => 'ADD', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'GHI' },
        'data' => { 'field' => 'delivery' },
      })
      write_change('701-001-LIR-ABC.yaml', {
        'type' => 'LIR', 'ob_issue_no' => '701',
        'identifier' => { 'code' => 'ABC' },
        'reason' => { 'en' => 'x' },
      })
      s = replay.at_issue(701)
      expect(s.history.map { |c| [c.type, c.ob_issue_no] }).to eq([
        ['SEED', 669], ['ADD', 700], ['LIR', 701],
      ])
    end
  end

  describe '#current' do
    it 'applies every change regardless of cutoff' do
      write_change('1000-001-ADD-XYZ.yaml', {
        'type' => 'ADD', 'ob_issue_no' => '1000',
        'identifier' => { 'code' => 'XYZ' },
        'data' => { 'field' => 'x' },
      })
      s = replay.current
      expect(s.active_keys).to include('XYZ')
    end
  end

  describe 'LIR is reversible by REP' do
    it 'reactivates the entry' do
      write_change('700-001-LIR-ABC.yaml', {
        'type' => 'LIR', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'ABC' },
        'reason' => { 'en' => 'Deprecated' },
      })
      write_change('800-001-REP-ABC.yaml', {
        'type' => 'REP', 'ob_issue_no' => '800',
        'identifier' => { 'code' => 'ABC' },
        'data' => { 'field' => 'delivery', 'message' => { 'en' => 'reactivated' } },
      })
      s = replay.at_issue(800)
      expect(s.active_keys).to include('ABC')
      expect(s.lapsed_keys).not_to include('ABC')
    end
  end

  describe 'returns frozen State' do
    it 'is frozen' do
      expect(replay.at_issue(669)).to be_frozen
    end

    it 'deep-freezes entry row hashes' do
      state = replay.at_issue(669)
      entry = state.entries.values.first
      expect(entry).to be_frozen
      expect {
        entry['hacked'] = 'yes'
      }.to raise_error(FrozenError)
    end
  end

  describe 'error tracking' do
    it 'increments error_count when a conflicting ADD is encountered' do
      # Seed already has ABC. ADD ABC again should conflict.
      write_change('700-001-ADD-ABC.yaml', {
        'type' => 'ADD', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'ABC' },
        'data' => { 'field' => 'x' },
      })
      state = replay.at_issue(700)
      expect(state.error_count).to be > 0
    end

    it 'has zero errors for clean replay' do
      state = replay.at_issue(669)
      expect(state.error_count).to eq(0)
    end
  end

  describe 'build_all_states captures only at issue boundaries' do
    it 'captures one state per unique issue' do
      write_change('700-001-ADD-GHI.yaml', {
        'type' => 'ADD', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'GHI' },
        'data' => { 'field' => 'delivery' },
      })
      write_change('700-002-ADD-JKL.yaml', {
        'type' => 'ADD', 'ob_issue_no' => '700',
        'identifier' => { 'code' => 'JKL' },
        'data' => { 'field' => 'delivery' },
      })
      write_change('800-001-ADD-MNO.yaml', {
        'type' => 'ADD', 'ob_issue_no' => '800',
        'identifier' => { 'code' => 'MNO' },
        'data' => { 'field' => 'delivery' },
      })

      all_states = replay.build_all_states
      # Should have states for 669 (seed), 700, 800, and nil (current).
      expect(all_states.keys.compact.sort).to eq([669, 700, 800])
      expect(all_states).to have_key(nil)

      # State at 700 should reflect BOTH ADD-700 changes.
      state_700 = all_states[700]
      expect(state_700.active_keys).to contain_exactly('ABC', 'DEF', 'GHI', 'JKL')
    end
  end
end
