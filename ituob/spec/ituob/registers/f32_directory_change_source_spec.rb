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

  it "fails closed when the verified publication is absent instead of falling back to the legacy seed" do
    expect { source }.to raise_error(RuntimeError, /publication\.yaml is missing.*not a fallback.*build_f32_seed_publication/m)
  end

  it "fails closed with an actionable error when the publication file is empty" do
    File.write(File.join(seed_dir, "publication.yaml"), "")
    expect { source }.to raise_error(RuntimeError, /unreadable.*build_f32_seed_publication/m)
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
    expect(source.publication.contexts.map(&:to_yaml)).to eq(complete.contexts.map(&:to_yaml))
    expect(source.each_sorted.first.data.map { |entry| entry.fetch("office_code") }).to all(match(/\S/))
    expect(File.binread(File.join(seed_dir, "data.yaml"))).to eq(File.binread(legacy_seed))
    register = Ituob::Catalogs::Registers.find("F32_TDI")
    replay = Ituob::Registers::Replay.new(register_id: "F32_TDI", key_field: register.key_field, source: source)
    result = Ituob::Verifiers::RegisterStateIntegrityVerifier.new.verify_state(replay.at_seed, register: register)
    expect(result.errors).to be_empty
  end
  context "with the committed publication and amendments" do
    let(:data_root) { File.expand_path("../../../../datasets/980-F.32", __dir__) }
    let(:committed) do
      described_class.new(register_id: "F32_TDI", seed_path: data_root, seed_issue: 980, key_field: "office_code")
    end
    let(:rep_rows) do
      Ituob::Support::Yaml.safe_load_file(File.join(data_root, "changes/0988-0001-REP-UNMY.yaml")).dig("data", "entries")
    end

    def replay_at(issue)
      Ituob::Registers::Replay.new(register_id: "F32_TDI", key_field: "office_code", source: committed).at_issue(issue)
    end

    it "accounts for all 473 printed OB 988 rows: one entry per indicator plus a shared-indicator context per extra row" do
      shared = committed.contexts_at_issue(988).select { |c| c.ob_issue_no == 988 && c.kind == "shared-indicator" }
      entries = committed.each_sorted.select { |c| c.ob_issue_no == 988 && c.type == "REP" }.flat_map { |c| c.data["entries"] }
      expect(rep_rows.length).to eq(473)
      expect(entries.length + shared.length).to eq(473)
      expect(entries.map { |e| e["office_code"] }).to eq(rep_rows.map { |e| e["office_code"] }.uniq)
      unae = shared.select { |c| c.related_office_code == "UNAE" }
      expect(unae.map { |c| c.entry.telegraph_office_name.en }).to eq(["ABASIA EGYPT /B", "PHON ASIOUT 1", "PHON ASIOUT 2"])
      expect(unae.map(&:source_row)).to eq(unae.map(&:source_row).sort)
    end

    it "keeps the first printed row of a shared indicator, as the seed does, and replaces the unprinted seed UN offices" do
      state = replay_at(988)
      unae = state.entries.fetch("UNAE")
      expect(unae.dig("telegraph_office_name", "en")).to eq("ABASIA EGYPT")
      expect(state.entries.keys.grep(/\AUN/)).to match_array(rep_rows.map { |e| e["office_code"] }.uniq.select { |c| c.start_with?("UN") })
      expect(state.entries.keys).not_to include("UNAK", "UNPO")
      expect(state.deleted_keys).to include("UNAK", "UNPO")
    end

    it "rejects a grouped REP loudly, naming the OB and code, before any state is produced" do
      path = File.join(seed_dir, "changes")
      FileUtils.mkdir_p(path)
      FileUtils.cp(File.join(data_root, "publication.yaml"), File.join(seed_dir, "publication.yaml"))
      FileUtils.cp(File.join(data_root, "metadata.yaml"), File.join(seed_dir, "metadata.yaml")) if File.exist?(File.join(data_root, "metadata.yaml"))
      File.write(File.join(path, "1200-0001-REP-X.yaml"), {
        "type" => "REP", "register" => "F32_TDI", "ob_issue_no" => "1200", "identifier" => { "code" => "MAAS" },
        "data" => { "entries" => [{ "office_code" => "MAAS MAIP" }] }
      }.to_yaml)
      replay = Ituob::Registers::Replay.new(register_id: "F32_TDI", key_field: "office_code", source: source)
      expect { replay.current }.to raise_error(RuntimeError, /only supported for SUP: OB 1200 "MAAS MAIP"/)
    end
  end
end
