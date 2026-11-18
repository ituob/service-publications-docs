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

  it "F5 accepts scalar values after actual model coercion" do
    row = { "country_code" => 42, "country_or_area" => { "en" => "x", "fr" => "x", "es" => "x" },
            "mobile_telephone_numbers" => { "en" => "x" } }
    model = Ituob::Models::E164BEntry.from_yaml(YAML.dump(row))
    expect(model.validate).to be_empty
    expect(model.country_code).to eq("42")
    expect(validate_parity_seed(@root, "1015-E.164B", [row])).to eq([true, nil])
    dataset = Ituob::Dataset.new(File.join(@root, "datasets", "1015-E.164B"))
    expect(dataset.data.first.fetch("country_code")).to eq(42)
  end

  it "preserves optional fields and required seed constraints after model normalization" do
    @mapping.each do |slug, name|
      [{}, { "unknown" => "ignored", "_class" => name }].each do |row|
        model = Ituob::Models.const_get(name).from_yaml(YAML.dump(row))
        expect(model.validate).to be_empty
        schema = YAML.load_file(File.join(@root, "datasets", slug, "schema-data.yaml"))
        if schema.fetch("items").fetch("required", []).empty?
          expect(validate_parity_seed(@root, slug, [row])).to eq([true, nil]), slug
        else
          expect(validate_parity_seed(@root, slug, [row]).first).to be(false), slug
        end
      end
    end
  end

  it "preserves model rejection of invalid status values" do
    row = { "status" => "invalid" }
    expect(Ituob::Models::E164DNotePQEntry.from_yaml(YAML.dump(row)).validate).not_to be_empty
    expect(validate_parity_seed(@root, "1114-E.164D-Note-PQ", [row]).first).to be(false)
  end
end
