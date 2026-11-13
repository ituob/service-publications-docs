# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"
require "yaml"

RSpec.describe "Authored SEED projection replay" do
  let(:repo_root) { File.expand_path("../../../..", __dir__) }
  let(:root) { Dir.mktmpdir("authored-seed") }
  let(:register_id) { "E212_MNC" }
  let(:registers) { [register_id] }
  let(:catalog_entry) { Ituob::Catalogs::Registers.find(register_id) }
  let(:rows) do
    [
      { "mcc_mnc_codes" => "230 01", "country_or_area" => { "en" => "Czech Republic" }, "networks" => "First" },
      { "mcc_mnc_codes" => "230 02", "country_or_area" => { "en" => "Czech Republic" }, "networks" => "Second" },
    ]
  end
  let(:amendment) { { "_class" => "E212MNCAmendment", "entries" => rows } }
  let(:patch_path) { File.join(root, "ob-issues/1351/e212-mnc/001-SEED.yaml") }
  let(:patch_bytes) do
    { "type" => "SEED", "ob_issue_no" => "1351", "identifier" => { "code" => "1351-001" },
      "data" => amendment }.to_yaml
  end
  let(:source) do
    Ituob::Registers::DirectoryChangeSource.new(
      register_id: register_id,
      seed_path: File.join(root, catalog_entry.seed_path),
      seed_issue: catalog_entry.seed_issue,
      key_field: catalog_entry.key_field,
    )
  end
  let(:change) { source.each_sorted.first }
  let(:replay) do
    Ituob::Registers::Replay.new(
      register_id: register_id,
      key_field: catalog_entry.key_field,
      source: source,
      fallback_key_fields: catalog_entry.fallback_key_fields,
    )
  end
  let(:state) { replay.at_issue(1351) }

  before do
    FileUtils.mkdir_p(File.join(root, "scripts"))
    FileUtils.cp(File.join(repo_root, "scripts/migrate_actions_to_changes.rb"), File.join(root, "scripts"))
    FileUtils.ln_s(File.join(repo_root, "ituob"), File.join(root, "ituob"))
    FileUtils.mkdir_p(File.dirname(patch_path))
    File.binwrite(patch_path, patch_bytes)
    _output, error, status = Open3.capture3(
      RbConfig.ruby, File.join(root, "scripts/migrate_actions_to_changes.rb"), registers.join(","), chdir: root,
    )
    expect(status).to be_success, error
  end

  after { FileUtils.remove_entry(root) }

  it "validates authored rows through the real compiled entry model" do
    model = Ituob::Models::E212MNCAmendment.from_hash(amendment)

    expect(model.entries).to all(be_a(Ituob::Models::E212MNCEntry))
    expect(model.entries.map(&:mcc_mnc_codes)).to eq(["230 01", "230 02"])
  end

  it "preserves batch rows through the real change LML round-trip" do
    round_trip = Ituob::Registers::Change.from_yaml(change.to_yaml)

    expect(change.data).to eq(amendment)
    expect(round_trip.data).to eq(change.data)
  end

  it "replays every projected row with its full payload" do
    expect(state.error_count).to eq(0)
    expect(state.entries).to eq(rows.to_h { |row| [row.fetch("mcc_mnc_codes"), row] })
    expect(state.history.map(&:type)).to eq(["SEED"])
  end

  it "keeps the authored patch bytes unchanged" do
    state

    expect(File.binread(patch_path)).to eq(patch_bytes)
  end

  context "with one authored row" do
    let(:rows) { [super().first] }

    it "preserves the flat hash wire format and replays the row" do
      round_trip = Ituob::Registers::Change.from_yaml(change.to_yaml)

      expect(round_trip.data).to eq(rows.first)
      expect(state.error_count).to eq(0)
      expect(state.entries).to eq({ "230 01" => rows.first })
    end
  end

  context "with routed shared rows" do
    let(:registers) { ["E212_MNC", "E212_SHARED_MCC"] }
    let(:rows) do
      [
        { "mcc_mnc_codes" => "901 65", "networks" => "Shared first" },
        { "mcc_mnc_codes" => "230 01", "networks" => "National" },
        { "mcc_mnc_codes" => "901 66", "networks" => "Shared second" },
      ]
    end

    it "keeps shared rows out of the main register" do
      expect(state.error_count).to eq(0)
      expect(state.entries).to eq({ "230 01" => rows[1] })
    end

    context "when replaying the shared register" do
      let(:register_id) { "E212_SHARED_MCC" }

      it "replays only the owned batch rows after LML round-trip" do
        round_trip = Ituob::Registers::Change.from_yaml(change.to_yaml)

        expect(round_trip.data).to eq(amendment.merge("entries" => [rows.first, rows.last]))
        expect(state.error_count).to eq(0)
        expect(state.entries).to eq({ "901 65" => rows.first, "901 66" => rows.last })
      end
    end
  end

  context "with an existing array seed publication" do
    let(:seed_row) { { "mcc_mnc_codes" => "230 00", "networks" => "Existing publication" } }

    before do
      File.write(File.join(root, catalog_entry.seed_path, "data.yaml"), [seed_row].to_yaml)
    end

    it "preserves the original array seed and adds the authored hash batch" do
      expect(replay.at_seed.entries).to eq({ "230 00" => seed_row })
      expect(source.each_sorted.first.data).to eq([seed_row])
      expect(state.error_count).to eq(0)
      expect(state.entries.keys).to contain_exactly("230 00", "230 01", "230 02")
      expect(state.entries.fetch("230 00")).to eq(seed_row)
    end
  end
end
