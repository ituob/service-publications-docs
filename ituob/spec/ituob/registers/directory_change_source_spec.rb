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
