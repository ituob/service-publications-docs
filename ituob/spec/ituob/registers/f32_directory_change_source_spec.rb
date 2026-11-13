# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "ituob/models"
require "ituob/registers"

RSpec.describe Ituob::Registers::F32DirectoryChangeSource do
  let(:seed_dir) { Dir.mktmpdir("f32-source") }
  let(:legacy_seed) { File.expand_path("../../../../datasets/980-F.32/data.yaml", __dir__) }
  let(:publication) { Ituob::Models::F32SeedBuilder.new(seed_path: File.join(seed_dir, "data.yaml")).build }
  let(:source) do
    described_class.new(register_id: "F32_TDI", seed_path: seed_dir, seed_issue: 980,
                        key_field: %w[country_or_area network_code office_code])
  end
  before { FileUtils.cp(legacy_seed, File.join(seed_dir, "data.yaml")) }
  after { FileUtils.remove_entry(seed_dir) }

  it "makes the unverified legacy fallback explicit when no publication is pinned" do
    expect { source }.to output(/legacy data.yaml.*not been verified/).to_stderr
    expect(source).to be_legacy_seed
    expect(source.each_sorted.first.data.length).to eq(Ituob::Support::Yaml.safe_load_file(legacy_seed).length)
  end

  it "rejects an artifact whose completeness has not been independently verified" do
    File.write(File.join(seed_dir, "publication.yaml"), publication.to_yaml)
    expect { source }.to raise_error(/independent allocation completeness/)
  end

  it "keeps a verified publication's context available while replaying only office allocations" do
    fixtures = File.expand_path("../../fixtures/f32", __dir__)
    complete = Ituob::Models::F32SeedBuilder.new(seed_path: File.join(seed_dir, "data.yaml")).build_complete(
      xml_path: File.join(fixtures, "official-2011.xml"), pdf_path: File.join(fixtures, "official-2011.pdf")
    )
    File.write(File.join(seed_dir, "publication.yaml"), complete.to_yaml)
    expect(source).not_to be_legacy_seed
    expect(source.publication.contexts.map(&:to_yaml)).to eq(complete.contexts.map(&:to_yaml))
    expect(source.each_sorted.first.data.map { |entry| entry.fetch("office_code") }).to all(match(/\S/))
    expect(File.binread(File.join(seed_dir, "data.yaml"))).to eq(File.binread(legacy_seed))
    register = Ituob::Catalogs::Registers.find("F32_TDI")
    replay = Ituob::Registers::Replay.new(register_id: "F32_TDI", key_field: register.key_field, source: source)
    result = Ituob::Verifiers::RegisterStateIntegrityVerifier.new.verify_state(replay.at_seed, register: register)
    expect(result.errors).to be_empty
  end
end
