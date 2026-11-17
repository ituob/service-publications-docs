# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'
require 'support/data_schema_generation'

RSpec.describe 'scripts/generate_data_schemas.rb' do
  include DataSchemaGeneration
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

  it 'merges the overlay over the LML-generated schema' do
    _out, err, status = run_generator
    expect(status.exitstatus).to eq(0), err
    items = YAML.load_file(schema_path)['items']
    expect(items['required']).to eq(['name'])
    expect(items['properties']['name']).to eq('type' => 'string', 'description' => 'Widget name')
    expect(items['properties']['size']).to eq('type' => 'integer')
  end

  it 'rejects overlays that override an evolved LML type' do
    write_overlay('1-W', 'items' => { 'properties' => { 'size' => { 'type' => 'string' } } })
    expect_failure('cannot change or remove LML-generated type')
  end

  it 'rejects removal of model types and properties' do
    write_overlay('1-W', 'type' => nil, 'items' => { 'properties' => { 'name' => nil } })
    expect_failure('cannot change or remove LML-generated type')
  end

  it 'rejects references that would bypass model type assertions' do
    write_overlay('1-W', 'items' => { 'properties' => { 'size' => { '$ref' => '#' } } })
    expect_failure('unknown overlay key "$ref"')
  end

  it 'rejects stale required references after a model field is removed' do
    write_overlay('1-W', 'items' => { 'required' => ['gone'] })
    expect_failure('required property "gone" is not in the final properties')
  end

  {
    'misspelled type' => { 'type' => 'strnig' },
    'scalar required' => { 'required' => 'name' },
    'scalar enum' => { 'enum' => 'abc' },
    'numeric additionalProperties' => { 'additionalProperties' => 7 },
    'numeric pattern' => { 'pattern' => 7 },
    'negative minLength' => { 'minLength' => -1 },
  }.each do |label, patch|
    it "rejects #{label} against the JSON Schema metaschema" do
      write_overlay('1-W', 'items' => { 'properties' => { 'name' => patch } })
      expect_failure('invalid JSON Schema')
    end
  end

  it 'rejects malformed regular expressions before writing' do
    write_overlay('1-W', 'items' => { 'properties' => { 'name' => { 'pattern' => '[' } } })
    expect_failure('invalid pattern')
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
