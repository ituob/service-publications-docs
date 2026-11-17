# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

module DataSchemaParity
  def build_parity_schemas(root, repo_root)
    ontology = "ituob/lib/ituob/ontology"
    FileUtils.mkdir_p(File.join(root, ontology))
    %w[messages.lml data_schemas.yaml data_schema_overlays].each do |name|
      FileUtils.cp_r(File.join(repo_root, ontology, name), File.join(root, ontology))
    end
    mapping = YAML.load_file(File.join(root, ontology, "data_schemas.yaml"))
    mapping.each_key { |slug| FileUtils.mkdir_p(File.join(root, "datasets", slug)) }
    _out, err, status = Open3.capture3(
      { "ITUOB_SCHEMA_ROOT" => root }, RbConfig.ruby,
      File.join(repo_root, "scripts/generate_data_schemas.rb")
    )
    raise err unless status.success?

    mapping
  end

  def validate_parity_seed(root, slug, rows)
    directory = File.join(root, "datasets", slug)
    File.write(File.join(directory, "data.yaml"),
               "# yaml-language-server: $schema=schema-data.yaml\n#{YAML.dump(rows)}")
    Ituob::Dataset.new(directory).validate_data
  end
end
