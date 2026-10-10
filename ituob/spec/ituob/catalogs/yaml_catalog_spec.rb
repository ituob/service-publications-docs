# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'yaml'
require 'ituob/catalogs'

# A minimal catalog used to test the YamlCatalog contract in isolation.
# Subclasses must declare: +yaml_key+, +primary_key+, +default_path+,
# +build_entry+, optionally +declare_indices+.
class TestWidgetCatalog
  class << self
    include Ituob::Catalogs::YamlCatalog

    Entry = Struct.new(:code, :label, keyword_init: true)

    def yaml_key
      'widgets'
    end

    def primary_key
      :code
    end

    def default_path
      # overridden in specs via load!(path:)
      '/dev/null'
    end

    def build_entry(hash)
      Entry.new(code: hash['code'], label: hash['label'])
    end
  end
end

RSpec.describe Ituob::Catalogs::YamlCatalog do
  let(:tmpdir) { Dir.mktmpdir('yaml-catalog-spec') }
  after { FileUtils.rm_rf(tmpdir) }

  let(:yaml_path) { File.join(tmpdir, 'widgets.yaml') }

  before do
    File.write(yaml_path, YAML.dump({
      'widgets' => [
        { 'code' => 'W1', 'label' => 'Widget 1' },
        { 'code' => 'W2', 'label' => 'Widget 2' },
      ],
    }))
    TestWidgetCatalog.reset!
  end

  describe '.load!' do
    it 'parses the YAML and indexes entries by primary key' do
      TestWidgetCatalog.load!(path: yaml_path)
      expect(TestWidgetCatalog.find('W1').label).to eq('Widget 1')
      expect(TestWidgetCatalog.find('W2').label).to eq('Widget 2')
    end

    it 'is idempotent — calling twice yields the same state' do
      TestWidgetCatalog.load!(path: yaml_path)
      first = TestWidgetCatalog.find('W1')
      TestWidgetCatalog.load!(path: yaml_path)
      second = TestWidgetCatalog.find('W1')
      expect(second.code).to eq(first.code)
    end

    it 'returns self for chaining' do
      expect(TestWidgetCatalog.load!(path: yaml_path)).to equal(TestWidgetCatalog)
    end
  end

  describe '.find' do
    it 'returns nil for unknown keys' do
      TestWidgetCatalog.load!(path: yaml_path)
      expect(TestWidgetCatalog.find('NOPE')).to be_nil
    end

    it 'coerces the lookup key to a string' do
      TestWidgetCatalog.load!(path: yaml_path)
      expect(TestWidgetCatalog.find(:W1).code).to eq('W1')
    end
  end

  describe '.all_keys and .all' do
    it 'lists everything' do
      TestWidgetCatalog.load!(path: yaml_path)
      expect(TestWidgetCatalog.all_keys.sort).to eq(%w[W1 W2])
      expect(TestWidgetCatalog.all.length).to eq(2)
    end
  end

  describe '.each' do
    it 'returns an enumerator when called without a block' do
      TestWidgetCatalog.load!(path: yaml_path)
      expect(TestWidgetCatalog.each).to be_a(Enumerator)
    end

    it 'yields each entry when called with a block' do
      TestWidgetCatalog.load!(path: yaml_path)
      codes = []
      TestWidgetCatalog.each { |e| codes << e.code }
      expect(codes.sort).to eq(%w[W1 W2])
    end
  end

  describe 'lazy loading' do
    it 'loads automatically on first find' do
      # Default path is /dev/null so the load will produce empty data,
      # but the call must not raise.
      TestWidgetCatalog.reset!
      expect { TestWidgetCatalog.find('whatever') }.not_to raise_error
    end
  end

  describe 'secondary indices via index_by / find_by' do
    let(:catalog_with_slug) do
      Class.new do
        class << self
          include Ituob::Catalogs::YamlCatalog

          Entry = Struct.new(:code, :slug, keyword_init: true)

          def yaml_key; 'items'; end
          def primary_key; :code; end
          def default_path; '/dev/null'; end

          def declare_indices
            index_by :slug
          end

          def build_entry(h)
            Entry.new(code: h['code'], slug: h['slug'])
          end
        end
      end
    end

    it 'indexes a second field and resolves via find_by' do
      path = File.join(tmpdir, 'items.yaml')
      File.write(path, YAML.dump({
        'items' => [
          { 'code' => 'A', 'slug' => 'alpha' },
          { 'code' => 'B', 'slug' => 'beta' },
        ],
      }))

      catalog_with_slug.reset!
      catalog_with_slug.load!(path: path)
      expect(catalog_with_slug.find_by(:slug, 'alpha').code).to eq('A')
      expect(catalog_with_slug.find_by(:slug, 'beta').code).to eq('B')
      expect(catalog_with_slug.find_by(:slug, 'unknown')).to be_nil
    end
  end

  describe '.reset!' do
    it 'clears all indices' do
      TestWidgetCatalog.load!(path: yaml_path)
      TestWidgetCatalog.reset!
      # After reset, accessing primary_index triggers a fresh load
      # (with the default path). Confirm the in-memory state is gone.
      expect(TestWidgetCatalog.instance_variable_get(:@loaded)).to be_falsey
    end
  end
end
