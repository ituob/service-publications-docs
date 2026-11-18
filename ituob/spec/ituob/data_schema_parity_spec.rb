# frozen_string_literal: true

require "spec_helper"
require "support/data_schema_parity"

RSpec.describe "generated seed schema and model acceptance" do
  include DataSchemaParity

  before(:context) do
    @root = Dir.mktmpdir("data-schema-parity")
    @mapping = build_parity_schemas(@root, File.expand_path("../../..", __dir__))
  end

  after(:context) do
    FileUtils.remove_entry(@root) if @root
  end

  it "F4 rejects scalar F.32 network_roa_note just as the model does" do
    row = { "country_or_area" => { "en" => "x", "fr" => "x", "es" => "x" },
            "network_roa_note" => 42 }
    expect { Ituob::Models::F32TDIEntry.from_yaml(YAML.dump(row)) }.to raise_error(StandardError)
    success, error = validate_parity_seed(@root, "980-F.32", [row])
    expect(success).to be(false), error
  end

  it "F4 preserves the root array type and accepts a valid F.32 note" do
    row = { "country_or_area" => { "en" => "x", "fr" => "x", "es" => "x" },
            "network_roa_note" => { "en" => "note", "fr" => "note", "es" => "note" } }
    expect(validate_parity_seed(@root, "980-F.32", [row])).to eq([true, nil])
    expect(validate_parity_seed(@root, "980-F.32", row).first).to be(false)
  end

  it "F5 accepts Chinese language values preserved by the model" do
    row = { "country_code" => "1", "country_or_area" => { "en" => "x", "fr" => "x", "es" => "x", "zh" => "中国" },
            "mobile_telephone_numbers" => { "en" => "x" } }
    model = Ituob::Models::E164BEntry.from_yaml(YAML.dump(row))
    expect(model.validate).to be_empty
    expect(model.country_or_area.zh).to eq("中国")
    expect(validate_parity_seed(@root, "1015-E.164B", [row])).to eq([true, nil])
  end

  it "rejects scalar types even when model consumers coerce them" do
    row = { "country_code" => 42, "country_or_area" => { "en" => "x", "fr" => "x", "es" => "x" },
            "mobile_telephone_numbers" => { "en" => "x" } }
    model = Ituob::Models::E164BEntry.from_yaml(YAML.dump(row))
    expect(model.validate).to be_empty
    expect(model.country_code).to eq("42")
    expect(validate_parity_seed(@root, "1015-E.164B", [row]).first).to be(false)
    dataset = Ituob::Dataset.new(File.join(@root, "datasets", "1015-E.164B"))
    expect(dataset.data.first.fetch("country_code")).to eq(42)
  end

  it "preserves optional fields and required seed constraints" do
    @mapping.each_key do |slug|
      schema = YAML.load_file(File.join(@root, "datasets", slug, "schema-data.yaml"))
      if schema.fetch("items").fetch("required", []).empty?
        expect(validate_parity_seed(@root, slug, [{}])).to eq([true, nil]), slug
      else
        expect(validate_parity_seed(@root, slug, [{}]).first).to be(false), slug
      end
    end
  end

  context "with the T.35 acceptance regression" do
    let(:row) do
      { "code_bit" => "11111111", "country_or_area" => { "en" => "x", "fr" => "x", "es" => "x" } }
    end

    it "accepts the original valid row" do
      expect(validate_parity_seed(@root, "1002-T.35", [row])).to eq([true, nil])
    end

    it "rejects an unknown field instead of silently dropping it" do
      success, error = validate_parity_seed(@root, "1002-T.35", [row.merge("typo" => "should fail")])
      expect(success).to be(false)
      expect(error).to include("typo")
    end

    it "rejects an integer binary code instead of coercing it to a string" do
      success, error = validate_parity_seed(@root, "1002-T.35", [row.merge("code_bit" => 11111111)])
      expect(success).to be(false)
      expect(error).to include("code_bit", "string")
    end

    it "rejects unknown fields within a nested model" do
      row.fetch("country_or_area")["typo"] = "should fail"
      success, error = validate_parity_seed(@root, "1002-T.35", [row])
      expect(success).to be(false)
      expect(error).to include("typo")
    end

    it "rejects wrong scalar types within a nested model" do
      row.fetch("country_or_area")["en"] = 42
      success, error = validate_parity_seed(@root, "1002-T.35", [row])
      expect(success).to be(false)
      expect(error).to include("en", "string")
    end
  end

  it "rejects unknown fields and wrong scalar types for all 40 datasets" do
    repo_root = File.expand_path("../../..", __dir__)
    expect(@mapping.size).to eq(40)
    @mapping.each_key do |slug|
      seed = YAML.load_file(File.join(repo_root, "datasets", slug, "data.yaml"),
                            permitted_classes: [Date], aliases: true)
      row = seed.first || {}
      expect(validate_parity_seed(@root, slug, [row])).to eq([true, nil]), slug
      success, error = validate_parity_seed(@root, slug, [row.merge("typo" => "should fail")])
      expect(success).to be(false), slug
      expect(error).to include("typo"), slug

      schema = YAML.load_file(File.join(@root, "datasets", slug, "schema-data.yaml"))
      field, property = schema.fetch("items").fetch("properties").find do |_name, definition|
        definition.key?("type")
      end
      if property
        wrong_type = Array(property.fetch("type")).include?("boolean") ? 42 : false
        success, error = validate_parity_seed(@root, slug, [row.merge(field => wrong_type)])
        expect(success).to be(false), "#{slug}: #{field}"
        expect(error).to include(field), slug
      else
        expect(schema.fetch("items").fetch("properties")).to be_empty, slug
        expect(validate_parity_seed(@root, slug, [false]).first).to be(false), slug
      end
    end
  end

  context "with F.400 structured address fields" do
    %w[helpdesk autoanswer contact_address].each do |field|
      it "rejects unknown keys in #{field}" do
        success, error = validate_parity_seed(@root, "974-F.400", [{ field => { "typo" => "x" } }])
        expect(success).to be(false)
        expect(error).to include("typo")
      end

      it "rejects non-string X.400 addresses in #{field}" do
        success, error = validate_parity_seed(@root, "974-F.400", [{ field => { "x400" => 42 } }])
        expect(success).to be(false)
        expect(error).to include("x400", "string")
      end
    end

    %w[helpdesk autoanswer].each do |field|
      it "rejects non-boolean availability in #{field}" do
        success, error = validate_parity_seed(@root, "974-F.400", [{ field => { "available" => "false" } }])
        expect(success).to be(false)
        expect(error).to include("available", "boolean")
      end
    end
  end

  it "preserves model rejection of invalid status values" do
    row = { "status" => "invalid" }
    expect(Ituob::Models::E164DNotePQEntry.from_yaml(YAML.dump(row)).validate).not_to be_empty
    expect(validate_parity_seed(@root, "1114-E.164D-Note-PQ", [row]).first).to be(false)
  end
end
