# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'set'
require 'ituob/verifiers'

RSpec.describe Ituob::Verifiers::CatalogIntegrityVerifier do
  # Minimal structs for testing — no doubles.
  FakeRec = Struct.new(:code)
  FakeReg = Struct.new(:register_id, :slug, :recommendation, :key_field,
                       :seed_path, :external, :seed_issue) do
    def external? = external == true
  end

  let(:tmp_root) { Dir.mktmpdir('civ-spec') }
  after { FileUtils.rm_rf(tmp_root) }

  def build_verifier(registers, recommendations)
    rec_cat = Struct.new(:entries).new(recommendations)
    rec_cat.define_singleton_method(:each) do |&blk|
      entries.each { |e| blk.call(e) }
    end

    reg_cat = Struct.new(:entries).new(registers)
    reg_cat.define_singleton_method(:each_entry) do |&blk|
      entries.each { |e| blk.call(e) }
    end

    described_class.new(
      registers_catalog: reg_cat,
      recommendations_catalog: rec_cat,
      root: tmp_root,
    )
  end

  describe '#verify' do
    it 'passes for consistent catalogs' do
      FileUtils.mkdir_p(File.join(tmp_root, 'datasets', '669-F.1'))
      File.write(File.join(tmp_root, 'datasets', '669-F.1', 'data.yaml'),
                 [{ 'code' => 'ABC', 'field' => 'x' }].to_yaml)

      v = build_verifier(
        [FakeReg.new('F1', 'f1', 'F.1', 'code', 'datasets/669-F.1', false, 669)],
        [FakeRec.new('F.1')],
      )
      r = v.verify
      expect(r.errors).to be_empty
      expect(r.warnings).to be_empty
    end

    it 'reports orphan recommendation' do
      v = build_verifier(
        [FakeReg.new('X1', 'x1', 'X.999', 'code', nil, false, nil)],
        [FakeRec.new('F.1')],
      )
      r = v.verify
      expect(r.errors).not_to be_empty
      expect(r.errors.first).to include('X.999')
    end

    it 'reports missing seed_path' do
      v = build_verifier(
        [FakeReg.new('X1', 'x1', 'F.1', 'code', 'datasets/nonexistent', false, 100)],
        [FakeRec.new('F.1')],
      )
      r = v.verify
      expect(r.errors.any? { |e| e.include?('nonexistent') }).to be true
    end

    it 'skips seed_path check for external registers' do
      v = build_verifier(
        [FakeReg.new('EXT', 'ext', 'F.1', 'code', 'nonexistent', true, nil)],
        [FakeRec.new('F.1')],
      )
      r = v.verify
      expect(r.errors).to be_empty
    end

    it 'warns on key_field mismatch' do
      FileUtils.mkdir_p(File.join(tmp_root, 'ds', '100'))
      File.write(File.join(tmp_root, 'ds', '100', 'data.yaml'),
                 [{ 'wrong_key' => 'x' }].to_yaml)

      v = build_verifier(
        [FakeReg.new('X1', 'x1', 'F.1', 'expected_key', 'ds/100', false, 100)],
        [FakeRec.new('F.1')],
      )
      r = v.verify
      expect(r.warnings.any? { |w| w.include?('expected_key') }).to be true
    end
  end
end
