# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'ituob/verifiers'
require 'ituob/catalogs'

# A minimal stand-in registers catalog so the spec doesn't depend on
# the real catalogs/registers.yaml. Verifier is callable against any
# object that responds to +each_entry+ with entries shaped like
# Catalogs::Registers::Entry.
class FakeRegistersCatalog
  FakeEntry = Struct.new(
    :register_id, :slug, :recommendation, :key_field,
    :seed_issue, :seed_path, :external,
    keyword_init: true,
  ) do
    def external? = external == true
  end

  def initialize(entries)
    @entries = entries
  end

  def each_entry(&block)
    @entries.each(&block)
  end
end

RSpec.describe Ituob::Verifiers::SnapshotIntegrityVerifier do
  let(:tmpdir) { Dir.mktmpdir('snapshot-integrity-spec') }
  after { FileUtils.rm_rf(tmpdir) }

  let(:entry) do
    FakeRegistersCatalog::FakeEntry.new(
      register_id: 'TEST',
      slug: 'test',
      recommendation: 'X.999',
      key_field: 'code',
      seed_issue: 1000,
      seed_path: 'datasets/1000-Test',
      external: false,
    )
  end

  let(:catalog) { FakeRegistersCatalog.new([entry]) }

  def write_manifest(slug, fields)
    dir = File.join(tmpdir, slug)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate(fields))
  end

  def write_current(slug, fields)
    dir = File.join(tmpdir, slug)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'current.json'), JSON.generate(fields))
  end

  describe '#verify' do
    it 'passes when the manifest matches the catalog and entries exist' do
      write_manifest('test', {
                       'slug' => 'test',
                       'key_field' => 'code',
                       'seed_issue' => 1000,
                       'register_id' => 'TEST',
                       'recommendation' => 'X.999',
                     })
      write_current('test', { 'entry_count' => 42 })

      result = described_class.new(registers_catalog: catalog,
                                   snapshots_root: tmpdir).verify
      expect(result.errors).to be_empty
      expect(result.warnings).to be_empty
      expect(result).to be_passed
    end

    it 'errors when the manifest file is missing' do
      result = described_class.new(registers_catalog: catalog,
                                   snapshots_root: tmpdir).verify
      expect(result.errors.first).to include('missing manifest')
      expect(result).not_to be_passed
    end

    it 'errors when key_field diverges from the catalog' do
      write_manifest('test', {
                       'key_field' => 'WRONG',
                       'seed_issue' => 1000,
                       'register_id' => 'TEST',
                       'recommendation' => 'X.999',
                     })
      write_current('test', { 'entry_count' => 1 })

      result = described_class.new(registers_catalog: catalog,
                                   snapshots_root: tmpdir).verify
      expect(result.errors.first).to include('manifest.key_field mismatch')
      expect(result.errors.first).to include('"code"', '"WRONG"')
    end

    it 'errors when seed_issue diverges' do
      write_manifest('test', {
                       'key_field' => 'code',
                       'seed_issue' => 9_999,
                       'register_id' => 'TEST',
                       'recommendation' => 'X.999',
                     })
      write_current('test', { 'entry_count' => 1 })

      result = described_class.new(registers_catalog: catalog,
                                   snapshots_root: tmpdir).verify
      expect(result.errors.first).to include('manifest.seed_issue mismatch')
    end

    it 'warns when current.json has 0 entries despite a declared seed' do
      write_manifest('test', {
                       'key_field' => 'code',
                       'seed_issue' => 1000,
                       'register_id' => 'TEST',
                       'recommendation' => 'X.999',
                     })
      write_current('test', { 'entry_count' => 0 })

      result = described_class.new(registers_catalog: catalog,
                                   snapshots_root: tmpdir).verify
      expect(result.errors).to be_empty
      expect(result.warnings.first).to include('0 active entries')
    end

    it 'skips external registers' do
      external = FakeRegistersCatalog::FakeEntry.new(
        register_id: 'EXT', slug: 'ext', recommendation: 'X.000',
        key_field: 'code', seed_issue: nil, seed_path: nil, external: true,
      )
      cat = FakeRegistersCatalog.new([external])
      result = described_class.new(registers_catalog: cat,
                                   snapshots_root: tmpdir).verify
      expect(result.errors).to be_empty
    end

    it 'records an error when manifest.json contains invalid JSON' do
      dir = File.join(tmpdir, 'test')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'manifest.json'), '{ this is not valid json')

      result = described_class.new(registers_catalog: catalog,
                                   snapshots_root: tmpdir).verify
      expect(result.errors.first).to include('invalid JSON at')
      expect(result.errors.first).to include('TEST')
      expect(result.errors.first).to include('manifest.json')
    end

    it 'records an error when current.json contains invalid JSON' do
      write_manifest('test', {
                       'key_field' => 'code',
                       'seed_issue' => 1000,
                       'register_id' => 'TEST',
                       'recommendation' => 'X.999',
                     })
      dir = File.join(tmpdir, 'test')
      File.write(File.join(dir, 'current.json'), 'not json {{{')

      result = described_class.new(registers_catalog: catalog,
                                   snapshots_root: tmpdir).verify
      expect(result.errors.first).to include('invalid JSON at')
      expect(result.errors.first).to include('current.json')
    end
  end
end
