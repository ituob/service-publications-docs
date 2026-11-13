# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'ituob/registers'
require 'ituob/catalogs'

RSpec.describe Ituob::Registers::DirectoryChangeSource do
  let(:seed_dir) { Dir.mktmpdir('dcs-spec') }
  let(:changes_dir) { File.join(seed_dir, 'changes') }
  let(:register_id) { 'F1' }
  let(:seed_issue) { 669 }

  before do
    FileUtils.mkdir_p(changes_dir)
    File.write(File.join(seed_dir, 'data.yaml'), [
      { 'code' => 'ABC', 'field' => 'accounts' },
      { 'code' => 'DEF', 'field' => 'addresses' },
    ].to_yaml)
    File.write(File.join(changes_dir, '700-001-ADD-GHI.yaml'), {
      'type' => 'ADD', 'register' => 'F1', 'ob_issue_no' => '700',
      'identifier' => { 'code' => 'GHI' },
      'data' => { 'code' => 'GHI', 'field' => 'delivery' },
    }.to_yaml)
    File.write(File.join(changes_dir, '701-001-SUP-ABC.yaml'), {
      'type' => 'SUP', 'register' => 'F1', 'ob_issue_no' => '701',
      'identifier' => { 'code' => 'ABC' },
    }.to_yaml)
  end

  after { FileUtils.rm_rf(seed_dir) }

  let(:source) do
    described_class.new(
      register_id: register_id,
      seed_path: seed_dir,
      seed_issue: seed_issue,
      key_field: 'code',
    )
  end

  describe '#seed_issue' do
    it 'returns the seed issue number' do
      expect(source.seed_issue).to eq(669)
    end
  end

  describe 'replaying published annex seeds' do
    it 'preserves the effective date printed only in the E118 seed-issue patch' do
      entry = Ituob::Catalogs::Registers.find('E118_IIN')
      root = File.expand_path('../../../..', __dir__)
      annex_source = described_class.new(
        register_id: entry.register_id,
        seed_path: File.join(root, entry.seed_path),
        seed_issue: entry.seed_issue,
        key_field: entry.key_field,
      )
      replay = Ituob::Registers::Replay.new(
        register_id: entry.register_id, key_field: entry.key_field, source: annex_source,
      )

      state = replay.at_seed

      expect(state.entry_for('89 264 33').fetch('effective_date', nil)).to eq('1.VII.2018')
      expect(state.history.map(&:type)).to eq(['SEED'])
      expect(replay.current.entry_for('89 264 33').fetch('effective_date', nil)).to eq('1.VII.2018')
    end

    %w[E118_IIN Q708_ISPC E212_MNC].each do |register_id|
      it "does not replay amendments already included in the #{register_id} seed" do
        entry = Ituob::Catalogs::Registers.find(register_id)
        root = File.expand_path('../../../..', __dir__)
        annex_source = described_class.new(
          register_id: entry.register_id,
          seed_path: File.join(root, entry.seed_path),
          seed_issue: entry.seed_issue,
          key_field: entry.key_field,
        )
        replay = Ituob::Registers::Replay.new(
          register_id: entry.register_id,
          key_field: entry.key_field,
          source: annex_source,
          fallback_key_fields: entry.fallback_key_fields,
        )

        state = replay.at_seed

        expect(state.errors).to be_empty
        expect(state.history.map(&:type)).to eq(['SEED'])
        expect(state.entry_count).to be_positive
      end
    end
  end

  describe '#each_sorted' do
    it 'yields SEED first, then amendments in filename order' do
      changes = source.each_sorted.to_a
      expect(changes.length).to eq(3)
      expect(changes[0].action_type.seed?).to be true
      expect(changes[0].ob_issue_no).to eq(669)
      expect(changes[1].action_type.add?).to be true
      expect(changes[1].ob_issue_no).to eq(700)
      expect(changes[2].action_type.sup?).to be true
      expect(changes[2].ob_issue_no).to eq(701)
    end

    context 'with patches before, at and after the seed issue' do
      let(:seed_issue) { 1161 }

      before do
        FileUtils.rm_rf(changes_dir)
        FileUtils.mkdir_p(changes_dir)
        [1160, 1161, 1162].each do |issue|
          File.write(File.join(changes_dir, "#{issue}-001-ADD-#{issue}.yaml"), {
            'type' => 'ADD', 'register' => register_id, 'ob_issue_no' => issue,
            'identifier' => { 'code' => issue.to_s },
            'data' => { 'code' => issue.to_s },
          }.to_yaml)
        end
      end

      it 'keeps seed-issue and later patches for an unflagged register' do
        expect(source.each_sorted.map { |c| [c.type, c.ob_issue_no] }).to eq([
          ['SEED', 1161], ['ADD', 1161], ['ADD', 1162],
        ])
      end

      context 'with a flagged register' do
        let(:register_id) { 'E118_IIN' }

        context 'when same-issue patches contain fields absent from the seed' do
          before do
            File.write(File.join(changes_dir, '1161-001-ADD-1161.yaml'), {
              'type' => 'ADD', 'register' => register_id, 'ob_issue_no' => 1161,
              'identifier' => { 'code' => 'ABC' },
              'data' => { 'entries' => [
                { 'code' => 'ABC', 'field' => 'patch wording', 'effective_date' => '1.VII.2018' },
                { 'code' => 'GONE', 'effective_date' => '1.VII.2018' },
              ] },
            }.to_yaml)
            File.write(File.join(changes_dir, '1161-002-SUP-ABC.yaml'), {
              'type' => 'SUP', 'register' => register_id, 'ob_issue_no' => 1161,
              'identifier' => { 'code' => 'ABC' },
              'data' => { 'code' => 'ABC', 'removal_note' => 'withdrawn' },
            }.to_yaml)
          end

          it 'fills missing fields without replacing seed content or restoring absent entries' do
            replay = Ituob::Registers::Replay.new(
              register_id: register_id, key_field: 'code', source: source,
            )
            state = replay.at_seed

            expect(state.active_keys).to eq(%w[ABC DEF])
            expect(state.entry_for('ABC')).to eq(
              'code' => 'ABC', 'field' => 'accounts', 'effective_date' => '1.VII.2018',
            )
            expect(state.history.map(&:type)).to eq(['SEED'])
            expect(replay.build_all_states.fetch(1161).entries).to eq(state.entries)
            expect(replay.current.entry_for('ABC')).to eq(state.entry_for('ABC'))
          end
        end

        it 'keeps the seed and later patches only' do
          expect(source.each_sorted.map { |c| [c.type, c.ob_issue_no] }).to eq([
            ['SEED', 1161], ['ADD', 1162],
          ])
        end

        it 'preserves the seed edition and applies later patches during replay' do
          replay = Ituob::Registers::Replay.new(
            register_id: register_id, key_field: 'code', source: source,
          )
          states = replay.build_all_states

          expect(states.keys).to eq([1161, 1162, nil])
          expect(states[1161].active_keys).to eq(%w[ABC DEF])
          expect(states[1162].active_keys).to eq(%w[ABC DEF 1162])
          expect(replay.current.active_entries).to eq(states[nil].active_entries)
          expect(replay.current.errors).to be_empty
        end

        context 'with a different seed edition' do
          let(:seed_issue) { 1160 }

          it 'does not apply the catalogued seed policy to another edition' do
            expect(source.each_sorted.map { |c| [c.type, c.ob_issue_no] }).to eq([
              ['SEED', 1160], ['ADD', 1160], ['ADD', 1161], ['ADD', 1162],
            ])
          end
        end
      end

      context 'with an uncatalogued register' do
        let(:register_id) { 'UNLISTED' }

        it 'keeps seed-issue patches' do
          expect(source.each_until(1161).map(&:type)).to eq(%w[SEED ADD])
        end
      end

      context 'without a seed issue' do
        let(:seed_issue) { nil }

        it 'keeps all patches' do
          expect(source.each_sorted.map(&:ob_issue_no)).to eq([nil, 1160, 1161, 1162])
        end
      end
    end
  end

  describe '#each_until' do
    it 'stops at the given ob_issue' do
      changes = source.each_until(700).to_a
      expect(changes.length).to eq(2) # SEED + ADD-700
      expect(changes.last.ob_issue_no).to eq(700)
    end

    it 'returns all changes when no cutoff' do
      changes = source.each_until(nil).to_a
      expect(changes.length).to eq(3)
    end
  end

  context 'when no seed data.yaml exists' do
    before { FileUtils.rm(File.join(seed_dir, 'data.yaml')) }

    it 'skips seed and yields amendments only' do
      changes = source.each_sorted.to_a
      expect(changes.length).to eq(2)
      expect(changes.all? { |c| !c.action_type.seed? }).to be true
    end
  end

  context 'when no changes/ directory exists' do
    before { FileUtils.rm_rf(changes_dir) }

    it 'yields only the seed' do
      changes = source.each_sorted.to_a
      expect(changes.length).to eq(1)
      expect(changes[0].action_type.seed?).to be true
    end
  end

  context 'with a malformed change file' do
    before do
      File.write(File.join(changes_dir, '999-001-BAD.yaml'), {
        'type' => 'BADTYPE', 'register' => 'F1', 'ob_issue_no' => '999',
        'identifier' => { 'code' => 'X' },
      }.to_yaml)
    end

    it 'skips the malformed file and continues' do
      changes = source.each_sorted.to_a
      # Should still get SEED + ADD + SUP (but not BADTYPE).
      expect(changes.length).to eq(3)
    end
  end
end
