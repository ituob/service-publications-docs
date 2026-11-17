# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

RSpec.describe 'scripts/generate_data_schemas.rb' do
  let(:repo_root) { File.expand_path('../../..', __dir__) }
  let(:lml) do
    <<~LML
      models Fixture {
        class WidgetEntry {
          attribute _class, String { default: "WidgetEntry" }
          attribute name, String
          attribute size, Integer
        }
      }
    LML
  end
  let(:schema_path) { File.join(@root, 'datasets/1-W/schema-data.yaml') }
  let(:good_overlay) do
    { 'items' => { 'required' => ['name'], 'properties' => { 'name' => { 'description' => 'Widget name' } } } }
  end

  around do |example|
    Dir.mktmpdir('data-schemas-spec') do |dir|
      @root = dir
      ontology = File.join(dir, 'ituob/lib/ituob/ontology')
      FileUtils.mkdir_p(File.join(ontology, 'data_schema_overlays'))
      FileUtils.mkdir_p(File.join(dir, 'datasets/1-W'))
      FileUtils.mkdir_p(File.join(dir, 'datasets/2-V'))
      File.write(File.join(ontology, 'messages.lml'), lml)
      File.write(File.join(ontology, 'data_schemas.yaml'), YAML.dump('1-W' => 'WidgetEntry'))
      write_overlay('1-W', good_overlay)
      File.write(schema_path, 'untouched')
      example.run
    end
  end

  def write_overlay(slug, content)
    path = File.join(@root, 'ituob/lib/ituob/ontology/data_schema_overlays', "#{slug}.yaml")
    File.write(path, content.is_a?(String) ? content : YAML.dump(content))
  end

  def run_generator
    Open3.capture3({ 'ITUOB_SCHEMA_ROOT' => @root }, RbConfig.ruby,
                   File.join(repo_root, 'scripts/generate_data_schemas.rb'))
  end

  def expect_failure(message)
    _out, err, status = run_generator
    expect(status.exitstatus).to eq(1)
    expect(err).to include(message)
    expect(File.read(schema_path)).to eq('untouched')
  end

  it 'merges the overlay over the LML-generated schema' do
    _out, err, status = run_generator
    expect(status.exitstatus).to eq(0), err
    items = YAML.load_file(schema_path)['items']
    expect(items['required']).to eq(['name'])
    expect(items['properties']['name']).to eq('type' => 'string', 'description' => 'Widget name')
    expect(items['properties']['size']).to eq('type' => 'integer')
  end

  it 'fails when an overlay property is not in the LML (1)' do
    write_overlay('1-W', 'items' => { 'properties' => { 'gone' => { 'description' => 'x' } } })
    expect_failure('1-W.items.properties.gone: not in the LML-generated schema')
  end

  it 'fails on an empty overlay file (2)' do
    write_overlay('1-W', '')
    expect_failure('1-W: overlay node must be a mapping')
  end

  it 'fails on a non-mapping overlay file (2)' do
    write_overlay('1-W', "- a\n- b\n")
    expect_failure('1-W: overlay node must be a mapping')
  end

  it 'fails on an unknown overlay keyword (3)' do
    write_overlay('1-W', 'items' => { 'requried' => ['name'] })
    expect_failure('unknown overlay key "requried"')
  end

  it 'fails on an orphan overlay file (4)' do
    write_overlay('9-Z', good_overlay)
    expect_failure('9-Z: overlay file has no entry in data_schemas.yaml')
  end

  it 'writes nothing when any dataset fails (5)' do
    ontology = File.join(@root, 'ituob/lib/ituob/ontology')
    File.write(File.join(ontology, 'data_schemas.yaml'), YAML.dump('1-W' => 'WidgetEntry', '2-V' => 'MissingEntry'))
    expect_failure('2-V: no LML class MissingEntry')
  end
end
