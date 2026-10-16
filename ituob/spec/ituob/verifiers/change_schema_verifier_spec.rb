# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'ituob/verifiers'

RSpec.describe Ituob::Verifiers::ChangeSchemaVerifier do
  let(:tmp_root) { Dir.mktmpdir('csv-spec') }
  let(:datasets_root) { File.join(tmp_root, 'datasets') }
  let(:changes_dir) { File.join(datasets_root, '669-F.1', 'changes') }

  # Minimal in-memory register catalog for testing — no doubles.
  FakeEntry = Struct.new(:register_id, :slug, :seed_path, :external) do
    def external? = external == true
  end

  FakeCatalog = Struct.new(:entries) do
    def each_entry
      return enum_for(:each_entry) unless block_given?
      entries.each { |e| yield e }
    end
  end

  before do
    FileUtils.mkdir_p(changes_dir)
    real_schema = File.expand_path('../../../../datasets/schema-change.yaml', __dir__)
    FileUtils.cp(real_schema, File.join(datasets_root, 'schema-change.yaml'))
  end

  after { FileUtils.rm_rf(tmp_root) }

  let(:fake_catalog) do
    FakeCatalog.new([
      FakeEntry.new('F1', 'f1', 'datasets/669-F.1', false),
    ])
  end

  subject(:verifier) do
    described_class.new(registers_catalog: fake_catalog, datasets_root: datasets_root)
  end

  def write_valid_change
    File.write(File.join(changes_dir, '700-001-ADD-XYZ.yaml'), {
      'type' => 'ADD',
      'register' => 'F1',
      'ob_issue_no' => '700',
      'identifier' => { 'code' => 'XYZ' },
      'data' => { 'code' => 'XYZ', 'field' => 'delivery' },
    }.to_yaml)
  end

  def write_invalid_change
    File.write(File.join(changes_dir, '701-001-BAD.yaml'), {
      'type' => 'BADTYPE',
      'register' => 'F1',
      'ob_issue_no' => '701',
      'identifier' => { 'code' => 'QQ' },
    }.to_yaml)
  end

  describe '#verify' do
    it 'counts valid files' do
      write_valid_change
      result = verifier.verify
      expect(result.stats[:valid]).to eq(1)
      expect(result.errors).to be_empty
    end

    it 'reports invalid files with errors' do
      write_invalid_change
      result = verifier.verify
      expect(result.stats[:invalid]).to eq(1)
      expect(result.errors).not_to be_empty
    end

    it 'handles a mix of valid and invalid' do
      write_valid_change
      write_invalid_change
      result = verifier.verify
      expect(result.stats[:valid]).to eq(1)
      expect(result.stats[:invalid]).to eq(1)
    end

    it 'returns a Result with the expected name' do
      expect(verifier.verify.name).to eq('ChangeSchemaVerifier')
    end
  end
end
