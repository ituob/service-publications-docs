# frozen_string_literal: true

require "spec_helper"
require "ituob/dataset"
require "fileutils"
require "tmpdir"

RSpec.describe Ituob::Dataset do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(temp_dir)
  end

  context "with a valid dataset" do
    let(:dataset_dir) { File.join(temp_dir, "test-dataset") }
    let(:dataset) { Ituob::Dataset.new(dataset_dir) }

    before do
      # Create a test dataset with all required files
      FileUtils.mkdir_p(dataset_dir)

      File.write(File.join(dataset_dir, "metadata.yaml"), <<~YAML)
        # yaml-language-server: $schema=../schema-metadata.yaml
        ---
        title:
          en: Test Dataset
          fr: Jeu de données de test
      YAML

      File.write(File.join(dataset_dir, "schema-data.yaml"), <<~YAML)
        ---
        $schema: http://json-schema.org/draft-07/schema#
        type: array
        items:
          type: object
          properties:
            name:
              type: string
            value:
              type: number
          required:
            - name
            - value
      YAML

      File.write(File.join(dataset_dir, "data.yaml"), <<~YAML)
        # yaml-language-server: $schema=schema-data.yaml
        ---
        - name: Item 1
          value: 123
        - name: Item 2
          value: 456
      YAML
    end

    it "has the correct name" do
      expect(dataset.name).to eq("test-dataset")
    end

    it "has valid structure" do
      expect(dataset.valid_structure?).to be true
    end

    it "reports having data" do
      expect(dataset.has_data?).to be true
    end

    it "loads metadata correctly" do
      expect(dataset.metadata["title"]["en"]).to eq("Test Dataset")
    end

    it "loads data correctly" do
      expect(dataset.data.size).to eq(2)
      expect(dataset.data[0]["name"]).to eq("Item 1")
    end

    it "returns correct dataset info" do
      info = dataset.info
      expect(info["directory"]).to eq("test-dataset")
      expect(info["title"]).to eq("Test Dataset")
      expect(info["has_data_file"]).to be true
      expect(info["has_data_directory"]).to be false
    end

    it "validates metadata against a schema" do
      schema_path = File.join(temp_dir, "schema-metadata.yaml")
      File.write(schema_path, <<~YAML)
        ---
        $schema: https://json-schema.org/draft/2020-12/schema
        type: object
        required:
          - title
        properties:
          title:
            type: object
      YAML

      success, error = dataset.validate_metadata(schema_path)
      expect(success).to be true
      expect(error).to be_nil
    end

    it "validates data against its schema" do
      success, error = dataset.validate_data
      expect(success).to be true
      expect(error).to be_nil
    end
  end

  context "with a dataset using data directory" do
    let(:dataset_dir) { File.join(temp_dir, "data-dir-dataset") }
    let(:dataset) { Ituob::Dataset.new(dataset_dir) }

    before do
      # Create a test dataset with data directory
      FileUtils.mkdir_p(File.join(dataset_dir, "data"))

      File.write(File.join(dataset_dir, "metadata.yaml"), <<~YAML)
        # yaml-language-server: $schema=../schema-metadata.yaml
        ---
        title:
          en: Data Directory Dataset
      YAML

      File.write(File.join(dataset_dir, "schema-data.yaml"), <<~YAML)
        ---
        $schema: http://json-schema.org/draft-07/schema#
        type: object
        properties:
          name:
            type: string
          value:
            type: number
        required:
          - name
          - value
      YAML

      File.write(File.join(dataset_dir, "data", "item1.yaml"), <<~YAML)
        # yaml-language-server: $schema=../schema-data.yaml
        ---
        name: Item 1
        value: 123
      YAML

      File.write(File.join(dataset_dir, "data", "item2.yaml"), <<~YAML)
        # yaml-language-server: $schema=../schema-data.yaml
        ---
        name: Item 2
        value: 456
      YAML
    end

    it "has valid structure" do
      expect(dataset.valid_structure?).to be true
    end

    it "reports having data" do
      expect(dataset.has_data?).to be true
    end

    it "finds data files" do
      expect(dataset.data_files.size).to eq(2)
    end

    it "loads data from all files" do
      expect(dataset.data.size).to eq(2)
    end

    it "returns correct dataset info" do
      info = dataset.info
      expect(info["has_data_file"]).to be false
      expect(info["has_data_directory"]).to be true
    end
  end

  context "with an invalid dataset" do
    let(:dataset_dir) { File.join(temp_dir, "invalid-dataset") }
    let(:dataset) { Ituob::Dataset.new(dataset_dir) }

    before do
      # Create a minimal invalid dataset
      FileUtils.mkdir_p(dataset_dir)
      File.write(File.join(dataset_dir, "metadata.yaml"), "title: Invalid")
    end

    it "reports invalid structure" do
      expect(dataset.valid_structure?).to be false
    end

    it "reports not having data" do
      expect(dataset.has_data?).to be false
    end

    it "returns empty data files list" do
      expect(dataset.data_files).to be_empty
    end

    it "returns nil for data" do
      expect(dataset.data).to be_nil
    end

    it "reports metadata validation failure" do
      schema_path = File.join(temp_dir, "schema-metadata.yaml")
      File.write(schema_path, <<~YAML)
        # yaml-language-server: $schema=https://json-schema.org/draft/2020-12/schema
        ---
        $schema: https://json-schema.org/draft/2020-12/schema
        type: object
        required:
          - title
        properties:
          title:
            type: object
      YAML

      success, error = dataset.validate_metadata(schema_path)
      expect(success).to be false
    end

    it "reports data validation failure" do
      # Create schema file but no data file
      File.write(File.join(dataset_dir, "schema-data.yaml"), "type: object")

      success, error = dataset.validate_data
      expect(success).to be false
    end
  end
end
