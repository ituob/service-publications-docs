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

  it 'rejects schemas outside the mapping before writing' do
    File.write(File.join(@root, 'datasets/2-V/schema-data.yaml'), 'unmapped')
    expect_failure('2-V: schema-data.yaml has no entry in data_schemas.yaml')
  end

  it 'rejects data seeds outside the mapping even without a schema' do
    File.write(File.join(@root, 'datasets/2-V/data.yaml'), '[]')
    expect_failure('2-V: schema-data.yaml has no entry in data_schemas.yaml')
  end

  context 'with a document schema' do
    let(:lml) do
      <<~LML
        models Fixture {
          enum Kind {
            member_fields {
              description String
            }
            alpha {
              description "first"
            }
            beta {
              description "second"
            }
          }
          class WidgetEntry {
            attribute name, String
          }
          class DocumentRow {
            attribute kind, Kind
            attribute label, String
            attribute schema, String
            attribute data, HashOrList
            mapping yaml {
              map "$schema", to: "schema"
            }
          }
        }
      LML
    end
    let(:document_path) { File.join(@root, 'datasets/doc.yaml') }

    before do
      File.write(File.join(@root, 'ituob/lib/ituob/ontology/document_schemas.yaml'),
                 YAML.dump('doc' => { 'model' => 'DocumentRow', 'path' => 'datasets/doc.yaml',
                                      'root' => 'object', 'id' => 'https://example.test/doc', 'title' => 'Doc' }))
      write_overlay('doc', 'description' => 'Caf\u00e9 document', 'required' => ['kind'], 'allOf' => [{ 'if' => { 'required' => ['kind'] } }])
    end

    it 'generates an object root with LML enums, wire keys and overlay conditionals' do
      _out, err, status = run_generator
      expect(status.exitstatus).to eq(0), err
      schema = YAML.load_file(document_path)
      expect(schema).to include('$id' => 'https://example.test/doc', 'type' => 'object', 'required' => ['kind'])
      expect(schema['properties']['kind']).to eq('type' => 'string', 'enum' => %w[alpha beta])
      expect(schema['properties'].keys).to eq(%w[kind label $schema data])
      expect(schema['properties']['data']).to eq('type' => %w[array object])
      expect(schema['allOf']).to eq([{ 'if' => { 'required' => ['kind'] } }])
    end

    it 'verifies and rejects an outdated document schema' do
      run_generator
      Open3.capture3('git', 'init', '--quiet', chdir: @root)
      Open3.capture3('git', 'add', 'datasets/doc.yaml', 'datasets/1-W/schema-data.yaml', chdir: @root)
      out, err, status = run_generator('--verify')
      expect(status.success?).to be(true), err
      expect(out).to include('Verified 2 generated data schemas')
      File.write(document_path, 'outdated')
      _out, err, status = run_generator('--verify')
      expect(status.exitstatus).to eq(1)
      expect(err).to include('doc: doc.yaml is missing or outdated')
    end

    it 'rejects a document schema with an unknown model' do
      File.write(File.join(@root, 'ituob/lib/ituob/ontology/document_schemas.yaml'),
                 YAML.dump('doc' => { 'model' => 'Gone', 'path' => 'datasets/doc.yaml', 'root' => 'object', 'title' => 'Doc' }))
      _out, err, status = run_generator
      expect(status.exitstatus).to eq(1)
      expect(err).to include('doc: no LML class Gone')
    end
  end

  context 'with verification enabled' do
    before do
      _out, err, status = run_generator
      expect(status.success?).to be(true), err
      _out, err, status = Open3.capture3('git', 'init', '--quiet', chdir: @root)
      expect(status.success?).to be(true), err
      _out, err, status = Open3.capture3('git', 'add', 'datasets/1-W/schema-data.yaml', chdir: @root)
      expect(status.success?).to be(true), err
    end

    it 'verifies current tracked schemas without writing' do
      before = File.stat(schema_path).mtime
      out, err, status = run_generator('--verify')
      expect(status.success?).to be(true), err
      expect(out).to include('Verified 1 generated data schemas')
      expect(File.stat(schema_path).mtime).to eq(before)
    end

    it 'rejects outdated schemas without repairing them' do
      File.write(schema_path, 'outdated')
      _out, err, status = run_generator('--verify')
      expect(status.exitstatus).to eq(1)
      expect(err).to include('schema-data.yaml is missing or outdated')
      expect(File.read(schema_path)).to eq('outdated')
    end

    it 'rejects missing schemas without creating them' do
      File.unlink(schema_path)
      _out, err, status = run_generator('--verify')
      expect(status.exitstatus).to eq(1)
      expect(err).to include('schema-data.yaml is missing or outdated')
      expect(File.exist?(schema_path)).to be(false)
    end

    it 'rejects untracked schemas even when their contents are current' do
      _out, err, status = Open3.capture3('git', 'rm', '--cached', 'datasets/1-W/schema-data.yaml', chdir: @root)
      expect(status.success?).to be(true), err
      before = File.binread(schema_path)
      _out, err, status = run_generator('--verify')
      expect(status.exitstatus).to eq(1)
      expect(err).to include('schema is not tracked by git')
      expect(File.binread(schema_path)).to eq(before)
    end
  end

end
