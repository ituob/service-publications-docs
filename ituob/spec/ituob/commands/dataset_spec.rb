# frozen_string_literal: true

require "spec_helper"
require "ituob/commands/dataset"
require "fileutils"
require "tmpdir"

RSpec.describe Ituob::Commands::Dataset do
  let(:temp_dir) { Dir.mktmpdir }
  let(:command) { described_class.new }

  before do
    # Allow command to use options hash for testing
    allow(command).to receive(:options).and_return(options)
  end

  after do
    FileUtils.remove_entry(temp_dir)
  end

  describe "#validate" do
    let(:options) do
      {
        datasets_root: File.join(temp_dir, "datasets"),
        metadata_schema: File.join(temp_dir, "schema-metadata.yaml"),
        verbose: true
      }
    end

    before do
      # Set up test environment with basic dataset
      FileUtils.mkdir_p(File.join(temp_dir, "datasets", "valid-dataset"))

      # Create metadata schema
      File.write(File.join(temp_dir, "schema-metadata.yaml"), <<~YAML)
        ---
        $schema: https://json-schema.org/draft/2020-12/schema
        type: object
        required:
          - title
        properties:
          title:
            type: object
            required:
              - en
            properties:
              en:
                type: string
      YAML

      # Create valid dataset
      FileUtils.mkdir_p(File.join(temp_dir, "datasets", "valid-dataset"))
      File.write(File.join(temp_dir, "datasets", "valid-dataset", "metadata.yaml"), <<~YAML)
        ---
        title:
          en: Valid Dataset
      YAML

      File.write(File.join(temp_dir, "datasets", "valid-dataset", "schema-data.yaml"), <<~YAML)
        ---
        $schema: http://json-schema.org/draft-07/schema#
        type: object
        properties:
          id:
            type: string
        required:
          - id
      YAML

      File.write(File.join(temp_dir, "datasets", "valid-dataset", "data.yaml"), <<~YAML)
        ---
        id: test-data
      YAML

      # Create invalid dataset
      FileUtils.mkdir_p(File.join(temp_dir, "datasets", "invalid-dataset"))
      File.write(File.join(temp_dir, "datasets", "invalid-dataset", "metadata.yaml"), <<~YAML)
        ---
        title:
          en: Invalid Dataset
      YAML

      File.write(File.join(temp_dir, "datasets", "invalid-dataset", "schema-data.yaml"), <<~YAML)
        ---
        $schema: http://json-schema.org/draft-07/schema#
        type: object
        properties:
          id:
            type: string
        required:
          - id
      YAML

      # Invalid data - missing required id field
      File.write(File.join(temp_dir, "datasets", "invalid-dataset", "data.yaml"), <<~YAML)
        ---
        name: missing-id
      YAML

      # Allow the tests to use our real validation logic but prevent actual exit
      allow(command).to receive(:exit)

      # Make sure the Dataset class creates real dataset objects
      # that will find these test files
      allow(Ituob::Dataset).to receive(:new).and_wrap_original do |method, path|
        # Create a real Dataset object
        dataset = method.call(path)

        # But add test spies to validate method calls
        allow(dataset).to receive(:validate_metadata).and_call_original
        allow(dataset).to receive(:validate_data).and_call_original

        dataset
      end
    end

    context "when validating all datasets" do
      it "reports validation results correctly" do
        # We expect two datasets to be validated
        expect(command).to receive(:validate_dataset).at_least(:twice).and_call_original

        # Run the command
        command.validate
      end
    end

    context "when validating a specific dataset" do
      let(:options) do
        {
          datasets_root: File.join(temp_dir, "datasets"),
          metadata_schema: File.join(temp_dir, "schema-metadata.yaml"),
          dataset: "valid-dataset",
          verbose: true
        }
      end

      it "validates only the specified dataset" do
        # We expect exactly one dataset to be validated
        expect(command).to receive(:validate_dataset).once.and_call_original

        # Run the command
        command.validate
      end
    end

    context "when validating a standalone dataset" do
      let(:options) do
        {
          standalone: File.join(temp_dir, "datasets", "valid-dataset"),
          metadata_schema: File.join(temp_dir, "schema-metadata.yaml"),
          verbose: true
        }
      end

      it "validates the standalone dataset" do
        # We expect exactly one dataset to be validated
        expect(command).to receive(:validate_dataset).once.and_call_original

        # Run the command
        command.validate
      end
    end
  end

  describe "#generate_manifest" do
    let(:options) do
      {
        datasets_root: File.join(temp_dir, "datasets"),
        output: File.join(temp_dir, "datasets.yaml"),
        verbose: true
      }
    end

    before do
      # Set up directories with datasets
      FileUtils.mkdir_p(File.join(temp_dir, "datasets", "dataset1"))
      FileUtils.mkdir_p(File.join(temp_dir, "datasets", "dataset2"))

      # Create valid dataset1
      File.write(File.join(temp_dir, "datasets", "dataset1", "metadata.yaml"), <<~YAML)
        ---
        title:
          en: Dataset One
      YAML

      File.write(File.join(temp_dir, "datasets", "dataset1", "schema-data.yaml"), "type: object")
      File.write(File.join(temp_dir, "datasets", "dataset1", "data.yaml"), "id: 1")

      # Create valid dataset2 with data directory
      File.write(File.join(temp_dir, "datasets", "dataset2", "metadata.yaml"), <<~YAML)
        ---
        title:
          en: Dataset Two
      YAML

      File.write(File.join(temp_dir, "datasets", "dataset2", "schema-data.yaml"), "type: object")

      # Create data directory with files
      FileUtils.mkdir_p(File.join(temp_dir, "datasets", "dataset2", "data"))
      File.write(File.join(temp_dir, "datasets", "dataset2", "data", "item1.yaml"), "id: 2")
    end

    it "generates a manifest file with correct dataset information" do
      command.generate_manifest

      # Read the generated manifest
      manifest = YAML.load_file(File.join(temp_dir, "datasets.yaml"))

      expect(manifest["datasets"].size).to eq(2)

      # Check dataset1 info
      dataset1 = manifest["datasets"].find { |d| d["directory"] == "dataset1" }
      expect(dataset1["title"]).to eq("Dataset One")
      expect(dataset1["has_data_file"]).to be true
      expect(dataset1["has_data_directory"]).to be false

      # Check dataset2 info
      dataset2 = manifest["datasets"].find { |d| d["directory"] == "dataset2" }
      expect(dataset2["title"]).to eq("Dataset Two")
      expect(dataset2["has_data_file"]).to be false
      expect(dataset2["has_data_directory"]).to be true
    end
  end
end
