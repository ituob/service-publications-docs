# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'ituob/registers'

RSpec.describe Ituob::Registers::DirectoryChangeSource do
  let(:seed_dir) { Dir.mktmpdir('dcs-spec') }
  let(:changes_dir) { File.join(seed_dir, 'changes') }

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
      register_id: 'F1',
      seed_path: seed_dir,
      seed_issue: 669,
      key_field: 'code',
    )
  end

  describe '#seed_issue' do
    it 'returns the seed issue number' do
      expect(source.seed_issue).to eq(669)
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
  end

  context 'with patches before and in the seed issue' do
    let(:seed_includes_seed_issue) { false }
    let(:source) do
      described_class.new(
        register_id: 'F1', seed_path: seed_dir, seed_issue: 669,
        key_field: 'code', seed_includes_seed_issue: seed_includes_seed_issue
      )
    end

    before do
      [668, 669].each do |issue|
        File.write(File.join(changes_dir, "#{issue}-001-ADD-XYZ.yaml"), {
          'type' => 'ADD', 'ob_issue_no' => issue,
          'identifier' => { 'code' => 'XYZ' },
          'data' => { 'code' => 'ABC', 'field' => 'accounts' }
        }.to_yaml)
      end
    end

    it 'retains same-issue patches by default and excludes older ones' do
      expect(source.each_sorted.map(&:ob_issue_no)).to eq([669, 669, 700, 701])
      expect(source.pre_seed_changes.map(&:ob_issue_no)).to eq([668])
    end

    context 'when the seed already includes its own issue' do
      let(:seed_includes_seed_issue) { true }

      [
        { 'code' => 'ABC', 'field' => 'different' },
        { 'code' => 'ABC', 'field' => 'accounts', 'effective_date' => '1.VII.2018' },
        { 'code' => 'XYZ', 'field' => 'accounts' },
        { 'code' => 'ABC', 'country' => { 'en' => 'Namibia' } },
        { 'entries' => [{ 'code' => 'ABC', 'field' => 'accounts' }, { 'code' => 'XYZ' }] },
        { 'notes' => ['unkeyed content'] }
      ].each do |payload|
        it "retains content not fully held by the seed: #{payload.inspect}" do
          File.write(File.join(changes_dir, '669-001-ADD-XYZ.yaml'), {
            'type' => 'ADD', 'ob_issue_no' => 669,
            'identifier' => { 'code' => 'XYZ' }, 'data' => payload
          }.to_yaml)

          expect(source.each_until(669).map(&:type)).to eq(%w[SEED ADD])
        end
      end

      it 'excludes a subset of nested seed fields without requiring all translations' do
        File.write(File.join(seed_dir, 'data.yaml'), [
          { 'code' => 'ABC', 'country' => { 'en' => 'Namibia', 'fr' => 'Namibie' } }
        ].to_yaml)
        File.write(File.join(changes_dir, '669-001-ADD-XYZ.yaml'), {
          'type' => 'LIR', 'ob_issue_no' => 669,
          'identifier' => { 'code' => 'ABC' },
          'data' => { 'code' => 'ABC', 'country' => { 'en' => 'Namibia' } }
        }.to_yaml)

        expect(source.each_until(669).map(&:type)).to eq(['SEED'])
      end

      it 'keeps a SUP when its target is still present in the seed' do
        File.write(File.join(changes_dir, '669-002-SUP-ABC.yaml'), {
          'type' => 'SUP', 'ob_issue_no' => 669,
          'identifier' => { 'code' => 'ABC' },
          'data' => { 'code' => 'ABC' }
        }.to_yaml)

        expect(source.each_until(669).map(&:type)).to eq(%w[SEED SUP])
      end

      it 'replays an otherwise identical ADD after a retained SUP of the same key' do
        File.write(File.join(changes_dir, '669-000-SUP-ABC.yaml'), {
          'type' => 'SUP', 'ob_issue_no' => 669,
          'identifier' => { 'code' => 'ABC' }, 'data' => { 'code' => 'ABC' }
        }.to_yaml)
        replay = Ituob::Registers::Replay.new(register_id: 'F1', key_field: 'code', source: source)

        expect(source.each_until(669).map(&:type)).to eq(%w[SEED SUP ADD])
        expect(replay.at_seed.entry_for('ABC')).to eq('code' => 'ABC', 'field' => 'accounts')
        expect(replay.at_seed.deleted_keys).to be_empty
      end

      it 'excludes a SUP only when all of its targets are absent' do
        File.write(File.join(changes_dir, '669-002-SUP-XYZ.yaml'), {
          'type' => 'SUP', 'ob_issue_no' => 669,
          'identifier' => { 'code' => 'XYZ' },
          'data' => { 'entries' => [{ 'code' => 'XYZ' }, { 'code' => 'NEW' }] }
        }.to_yaml)

        expect(source.each_until(669).map(&:type)).to eq(['SEED'])
      end

      it 'retains amendments when the seed file is missing' do
        FileUtils.rm(File.join(seed_dir, 'data.yaml'))

        expect(source.each_until(669).map(&:type)).to eq(['ADD'])
      end

      it 'excludes same-issue patches while retaining later patches and earlier evidence' do
        expect(source.each_sorted.map(&:ob_issue_no)).to eq([669, 700, 701])
        expect(source.each_until(669).map(&:type)).to eq(['SEED'])
        expect(source.pre_seed_changes.map(&:ob_issue_no)).to eq([668])
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
