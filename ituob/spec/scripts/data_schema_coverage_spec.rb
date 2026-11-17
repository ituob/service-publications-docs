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
end
