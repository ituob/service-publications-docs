# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json-schema"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

RSpec.describe "Dataset schema generation coverage" do
  let(:repo_root) { File.expand_path("../../..", __dir__) }
  let(:ontology) { File.join(repo_root, "ituob/lib/ituob/ontology") }
  let(:additional_mappings) do
    {
      "1001-T.35B" => "T35NAEntry",
      "1162-E.212" => "E212MNCEntry",
      "1162-E.212-Shared-MCC" => "E212MNCEntry",
      "994-E.164C" => "DPEntry",
      "icc" => "M1400Entry",
      "list-viii" => "ListVIIIStation",
      "nnp" => "NumberingPlanEntry",
    }
  end

  it "generates schemas for existing matching models and accepts their complete seeds" do
    mapping = YAML.load_file(File.join(ontology, "data_schemas.yaml"))
    expect(mapping).to include(additional_mappings)

    Dir.mktmpdir("data-schema-coverage") do |root|
      target = File.join(root, "ituob/lib/ituob/ontology")
      FileUtils.mkdir_p(File.join(target, "data_schema_overlays"))
      FileUtils.cp(File.join(ontology, "messages.lml"), target)
      File.write(File.join(target, "data_schemas.yaml"), YAML.dump(additional_mappings))
      additional_mappings.each_key do |slug|
        FileUtils.mkdir_p(File.join(root, "datasets", slug))
        overlay = File.join(ontology, "data_schema_overlays", "#{slug}.yaml")
        FileUtils.cp(overlay, File.join(target, "data_schema_overlays")) if File.file?(overlay)
      end

      _out, err, status = Open3.capture3(
        { "ITUOB_SCHEMA_ROOT" => root }, RbConfig.ruby,
        File.join(repo_root, "scripts/generate_data_schemas.rb"),
      )
      expect(status.exitstatus).to eq(0), err

      additional_mappings.each do |slug, class_name|
        generated = File.join(root, "datasets", slug, "schema-data.yaml")
        expect(File.read(generated)).to include("(#{class_name})")
        schema = YAML.load_file(generated)
        expect(schema.fetch("items").fetch("properties")).not_to be_empty
        seed = YAML.load_file(File.join(repo_root, "datasets", slug, "data.yaml"))
        schema.delete("$schema")
        expect(JSON::Validator.fully_validate(schema, seed)).to be_empty, slug
      end
    end
  end
  it "accepts printed effective dates, keyed notes and extra-territorial flags" do
    examples = {
      "1114-E.164D" => { "country_code" => "888", "notes" => ["k", "k Humanitarian purposes"] },
      "1114-E.164D-Note-N" => { "cc_ic" => "+881 9", "notes" => ["n"] },
      "1114-E.164D-Note-O" => { "cc_ic" => "+882 10", "notes" => ["o"] },
      "1114-E.164D-Note-PQ" => { "cc_ic" => "+883 5110", "notes" => ["q"] },
      "1162-E.212" => { "mcc_mnc_codes" => "262 74", "extra_territorial_use" => true },
      "1162-E.212-Shared-MCC" => { "mcc_mnc_codes" => "901 99", "extra_territorial_use" => true },
    }
    examples.each do |slug, entry|
      schema = YAML.load_file(File.join(repo_root, "datasets", slug, "schema-data.yaml"))
      schema.delete("$schema")
      row = entry.merge("effective_date" => "15 June 2012")
      expect(JSON::Validator.fully_validate(schema, [row])).to be_empty, slug
    end
  end

  it "covers every dataset schema and keeps all generated files current" do
    mapping = YAML.load_file(File.join(ontology, "data_schemas.yaml"))
    slugs = Dir.glob(File.join(repo_root, "datasets/*/schema-data.yaml")).map do |path|
      File.basename(File.dirname(path))
    end
    expect(mapping.keys.sort).to eq(slugs.sort)
    expect(mapping.size).to eq(40)
    out, err, status = Open3.capture3(
      RbConfig.ruby, File.join(repo_root, "scripts/generate_data_schemas.rb"), "--verify",
    )
    expect(status.success?).to be(true), err
    expect(out).to include("Verified 45 generated data schemas")
  end

  describe "document schemas" do
    let(:documents) { YAML.load_file(File.join(ontology, "document_schemas.yaml")) }

    def document_schema(name)
      YAML.load_file(File.join(repo_root, documents.fetch(name).fetch("path"))).tap do |schema|
        schema.delete("$schema")
        schema.delete("$id")
      end
    end

    def validation_errors(name, data)
      JSON::Validator.fully_validate(document_schema(name), JSON.parse(data.to_json))
    end

    def catalog(file, key)
      YAML.load_file(File.join(repo_root, "catalogs", file), aliases: true).fetch(key)
    end

    it "lists the five schemas that are not dataset seeds, each generated from its LML class" do
      expect(documents.keys).to contain_exactly(
        "schema-change", "schema-metadata", "schema-recommendation", "schema-register", "schema-countries",
      )
      documents.each_value do |spec|
        header = File.foreach(File.join(repo_root, spec.fetch("path"))).first
        expect(header).to include("GENERATED from ituob/lib/ituob/ontology/messages.lml (#{spec.fetch('model')})")
      end
    end

    it "validates every registers catalog row" do
      catalog("registers.yaml", "registers").each do |row|
        expect(validation_errors("schema-register", row)).to be_empty, row["register_id"]
      end
    end

    it "validates every recommendations catalog row" do
      catalog("recommendations.yaml", "recommendations").each do |row|
        expect(validation_errors("schema-recommendation", row)).to be_empty, row["code"]
      end
    end

    it "validates every dataset metadata file" do
      Dir.glob(File.join(repo_root, "datasets/*/metadata.yaml")).each do |path|
        data = YAML.load_file(path, permitted_classes: [Date], aliases: true)
        expect(validation_errors("schema-metadata", data)).to be_empty, path
      end
    end

    it "validates the RR.25.1 country list" do
      path = File.join(repo_root, "datasets/1154-RR.25.1/countries.yaml")
      expect(validation_errors("schema-countries", YAML.load_file(path))).to be_empty
    end

    it "validates every change file structurally" do
      # 976-X.121A/changes holds four illustrative patches without a register.
      paths = Dir.glob(File.join(repo_root, "datasets/*/changes/*.yaml")).grep_v(%r{976-X\.121A/changes/})
      failures = paths.filter_map do |path|
        data = YAML.load_file(path, permitted_classes: [Date, Time], aliases: true)
        errors = validation_errors("schema-change", data)
        "#{path}: #{errors.first}" unless errors.empty?
      end
      expect(failures).to be_empty
    end

    it "rejects what the catalogs and change files may not contain" do
      expect(validation_errors("schema-register", { "register_id" => "X" })).not_to be_empty
      expect(validation_errors("schema-register", catalog("registers.yaml", "registers").first.merge("x" => 1))).not_to be_empty
      expect(validation_errors("schema-recommendation", { "code" => "E.1", "bureau" => "ITU-X", "title" => { "en" => "t" } })).not_to be_empty
      change = { "type" => "ADD", "register" => "F1", "ob_issue_no" => "700", "identifier" => { "code" => "A" } }
      expect(validation_errors("schema-change", change)).to be_empty
      expect(validation_errors("schema-change", change.merge("type" => "BAD"))).not_to be_empty
      expect(validation_errors("schema-change", change.merge("ob_issue_no" => 700))).not_to be_empty
      expect(validation_errors("schema-change", change.merge("unknown" => 1))).not_to be_empty
    end
  end

  it "preserves required fields, code patterns and assignment enums" do
    examples = {
      "1002-T.35" => { "code_bit" => "invalid", "country_or_area" => { "en" => "x", "fr" => "x", "es" => "x" } },
      "1117-E.212A-MCCMNC" => { "mcc_mnc" => "901 01", "network" => "x", "status" => "invalid" },
      "1162-E.212-ET" => { "country_type" => "C" },
      "country-names" => { "key" => "x" },
    }
    examples.each do |slug, row|
      schema = YAML.load_file(File.join(repo_root, "datasets", slug, "schema-data.yaml"))
      schema.delete("$schema")
      expect(JSON::Validator.fully_validate(schema, [row])).not_to be_empty, slug
    end
  end

  it "preserves nullable fields and mixed numeric tone frequencies" do
    rows = {
      "roa" => { "country_or_area" => "x", "company_name" => nil },
      "bureaufax" => { "country_or_area" => "x", "location" => nil },
      "955-E.180" => { "country_or_area" => { "en" => "x" }, "tone_type" => "dial", "frequency_in_hz" => 440 },
    }
    rows.each do |slug, row|
      schema = YAML.load_file(File.join(repo_root, "datasets", slug, "schema-data.yaml"))
      schema.delete("$schema")
      expect(JSON::Validator.fully_validate(schema, [row])).to be_empty, slug
      row["unexpected"] = "x"
      expect(JSON::Validator.fully_validate(schema, [row])).not_to be_empty, slug
    end
  end

  it "accepts every complete dataset seed, including recursive call-sign groups" do
    mapping = YAML.load_file(File.join(ontology, "data_schemas.yaml"))
    mapping.each_key do |slug|
      schema = YAML.load_file(File.join(repo_root, "datasets", slug, "schema-data.yaml"))
      seed = YAML.load_file(File.join(repo_root, "datasets", slug, "data.yaml"),
                            permitted_classes: [Date], aliases: true)
      schema.delete("$schema")
      expect(JSON::Validator.fully_validate(schema, seed)).to be_empty, slug
    end
  end

  it "validates all complete raw seeds and models without losing explicit blanks" do
    mapping = YAML.load_file(File.join(ontology, "data_schemas.yaml"))
    mapping.each_key do |slug|
      dataset = Ituob::Dataset.new(File.join(repo_root, "datasets", slug))
      success, error = dataset.validate_data
      expect(success).to be(true), "#{slug}: #{error}"
    end
  end

  it "applies call-sign segment constraints through recursive references" do
    schema = YAML.load_file(File.join(repo_root, "datasets/1154-RR.25.1/schema-data.yaml"))
    schema.delete("$schema")
    nested = { "segment_type" => "string", "value" => "A" }
    row = { "country_or_area" => "x", "groups" => { "amateur" => [
      { "regex" => "A", "criteria" => [{ "segment_type" => "enum", "values" => [nested] }] },
    ] } }
    expect(JSON::Validator.fully_validate(schema, [row])).to be_empty
    nested["segment_type"] = "invalid"
    expect(JSON::Validator.fully_validate(schema, [row])).not_to be_empty
  end

end
