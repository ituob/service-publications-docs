# frozen_string_literal: true

module DataSchemaGeneration
  def write_overlay(slug, content)
    path = File.join(@root, 'ituob/lib/ituob/ontology/data_schema_overlays', "#{slug}.yaml")
    File.write(path, content.is_a?(String) ? content : YAML.dump(content))
  end

  def run_generator(*arguments)
    Open3.capture3({ 'ITUOB_SCHEMA_ROOT' => @root }, RbConfig.ruby,
                   File.join(repo_root, 'scripts/generate_data_schemas.rb'), *arguments)
  end

  def expect_failure(message)
    _out, err, status = run_generator
    expect(status.exitstatus).to eq(1)
    expect(err).to include(message)
    expect(File.read(schema_path)).to eq('untouched')
  end
end
