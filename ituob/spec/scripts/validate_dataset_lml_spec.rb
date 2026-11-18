# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

RSpec.describe "dataset LML instance validation" do
  let(:slug) { "1114-E.164D-Note-PQ" }
  let(:rows) { [{ "cc_ic" => "+883 5110", "status" => "Assigned" }] }
  let(:arguments) { ["--datasets-only"] }
  let(:result) do
    Open3.capture3(
      { "ITUOB_DATASETS_ROOT" => File.join(@root, "datasets") },
      RbConfig.ruby, File.join(@root, "scripts/validate_data_lml.rb"), *arguments,
    )
  end

  around do |example|
    Dir.mktmpdir("dataset-lml-validation") do |root|
      @root = root
      %w[scripts ob-issues catalogs].each { |dir| FileUtils.mkdir_p(File.join(root, dir)) }
      File.write(File.join(root, "catalogs/freeform_messages.yaml"), YAML.dump([]))
      FileUtils.ln_s(File.expand_path("../..", __dir__), File.join(root, "ituob"))
      FileUtils.cp(File.expand_path("../../../scripts/validate_data_lml.rb", __dir__),
                  File.join(root, "scripts"))
      directory = File.join(root, "datasets", slug)
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, "data.yaml"), YAML.dump(rows))
      example.run
    end
  end

  it "loads valid entries through the mapped Entry class without an issue corpus" do
    stdout, stderr, status = result
    expect(status.exitstatus).to eq(0), "#{stdout}\n#{stderr}"
    expect(stdout).to include("dataset files checked: 1; entries validated: 1", "DATASET INSTANCE DATA VALID")
  end

  context "with an invalid model enum" do
    let(:rows) { [{ "cc_ic" => "+883 5110", "status" => "deliberately-bad-status" }] }

    it "exits nonzero and identifies the bad data.yaml and model error" do
      stdout, stderr, status = result
      expect(status.exitstatus).to eq(1), stdout
      expect(stderr).to include("#{slug}/data.yaml", "row 0", "status")
      expect(stdout).not_to include("DATASET INSTANCE DATA VALID")
    end
  end

  context "with YAML aliases in a seed" do
    let(:slug) { "980-F.32" }
    let(:rows) do
      translation = { "en" => "Example", "fr" => "Exemple", "es" => "Ejemplo" }
      [{ "country_or_area" => translation, "network_roa_note" => translation }]
    end

    it "validates shared nested values without serializing aliases again" do
      expect(File.read(File.join(@root, "datasets", slug, "data.yaml"))).to include("*1")
      stdout, stderr, status = result
      expect(status.exitstatus).to eq(0), "#{stdout}\n#{stderr}"
      expect(stdout).to include("entries validated: 1")
    end
  end

  context "with a non-array seed" do
    let(:rows) { { "cc_ic" => "+883 5110" } }

    it "rejects the seed shape" do
      _stdout, stderr, status = result
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("expected an array of entries")
    end
  end

  context "with a scalar entry" do
    let(:rows) { ["bad"] }

    it "rejects the row shape" do
      _stdout, stderr, status = result
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("row 0: expected an entry mapping")
    end
  end

  context "with an unmapped dataset" do
    let(:slug) { "unmapped-dataset" }

    it "fails instead of skipping the file" do
      _stdout, stderr, status = result
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("unmapped-dataset/data.yaml", "no ontology Entry mapping")
    end
  end

  it "fails when no data files were discovered" do
    FileUtils.rm_rf(File.join(@root, "datasets", slug))
    _stdout, stderr, status = result
    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("no dataset data.yaml files found")
  end
end
