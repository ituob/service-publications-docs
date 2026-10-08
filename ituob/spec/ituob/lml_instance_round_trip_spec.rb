# frozen_string_literal: true

require 'spec_helper'
require 'lutaml/lml'
require 'stringio'

# Pending lutaml-lml release: 0.2.0's ModelCompiler#resolve_instance_value
# wraps a single nested instance in an Array even for non-collection
# attributes (its Format adapter unwraps singletons; the model compiler
# does not) and hydrates untyped nested instances as raw hashes instead
# of the attribute's type. Both are fixed in the lutaml-lml source,
# unreleased. Drop this module once a release with the fixes lands in
# ituob/Gemfile.lock.
module LmlInstanceRoundTripFixes
  def resolve_instance_value(value, nested, attr_def = nil)
    if nested.any?
      models = nested.map { |i| hydrate_typed(i, attr_def) }
      return models if attr_def&.collection?
      return models.first if models.one?
      return models
    end
    super
  end

  def hydrate_typed(instance, attr_def)
    return hydrate_instance(instance) if instance.isa || !instance.type.to_s.empty?

    type = attr_def&.type
    return hydrate_instance(instance) unless type.is_a?(Class)

    if type.include?(Lutaml::Model::Serialize)
      type.new(**extract_instance_attributes(instance, type))
    elsif type == Lutaml::Model::Type::Union
      extract_raw_attributes(instance)
    else
      hydrate_instance(instance)
    end
  end

  private :resolve_instance_value, :hydrate_typed
end

Lutaml::Lml::ModelCompiler.prepend(LmlInstanceRoundTripFixes)

OB_ISSUES_ROOT = File.expand_path('../../../ob-issues', __dir__)

# Every structured instance file in the corpus with its owning class;
# computed once per process (the walk reads ~8,000 YAML files).
def lml_round_trip_structured_files
  @lml_round_trip_structured_files ||= Dir.children(OB_ISSUES_ROOT).grep(/\A\d+\z/).sort.flat_map do |issue|
    dir = File.join(OB_ISSUES_ROOT, issue)
    Dir.glob(File.join(dir, '**', '*.yaml')).sort.filter_map do |path|
      rel = path.delete_prefix("#{dir}/")
      # Freeform positions are skipped before reading: their payloads
      # may contain YAML aliases the strict loader rejects.
      next if Ituob::Support::CorpusTree.class_name_for(rel).nil?

      data = YAML.load_file(path, permitted_classes: [Date, Time])
      resolved = Ituob::Support::CorpusTree.resolve_for(rel, data)
      next if resolved.nil? || !Ituob::Models.const_defined?(resolved)

      [path, "#{issue}/#{rel}", Ituob::Models.const_get(resolved)]
    end
  end
end

RSpec.describe 'LML instance round-trip (YAML instance == LML instance)' do
  def structured_files
    lml_round_trip_structured_files
  end

  def normalize_values(obj)
    case obj
    when Hash then obj.transform_values { |v| normalize_values(v) }
    when Array then obj.map { |v| normalize_values(v) }
    when Date, Time then obj.to_s
    else obj
    end
  end

  def normalized(obj)
    deep_compact(JSON.parse(JSON.generate(normalize_values(obj))))
  end

  # nil has no LML instance literal; nil keys are omitted on emit and
  # nulls are compacted on compare so absence and nil are equivalent.
  def deep_compact(obj)
    case obj
    when Hash then obj.each_with_object({}) do |(k, v), h|
      h[k] = deep_compact(v) unless v.nil?
    end
    when Array then obj.map { |v| deep_compact(v) }
    else obj
    end
  end

  # The grammar's bare word is [A-Za-z0-9_] and its value parser commits
  # to `number` on a leading digit run, so every non-word string must be
  # double-quoted (lutaml-lml 0.2.0 emits bare dash-bearing strings that
  # its own grammar cannot re-parse; fixed in the gem source, unreleased).
  def lml_scalar(value)
    case value
    when Integer, Float, TrueClass, FalseClass then value.to_s
    else "\"#{value}\""
    end
  end

  def lml_body(hash, indent)
    prefix = '  ' * indent
    hash.filter_map do |key, value|
      next if value.nil?

      rendered =
        case value
        when Hash
          "instance {\n#{lml_body(value, indent + 1)}\n#{prefix}}"
        when Array
          items = value.map do |item|
            if item.is_a?(Hash)
              "instance {\n#{lml_body(item, indent + 2)}\n#{'  ' * (indent + 1)}}"
            else
              "  #{lml_scalar(item)}"
            end
          end
          "[\n#{items.join(",\n")}\n#{prefix}]"
        else
          lml_scalar(value)
        end
      "#{prefix}#{key} = #{rendered}"
    end.join("\n")
  end

  def to_lml_instance(instance, type_name)
    "instance #{type_name} {\n#{lml_body(normalize_values(instance.to_hash), 1)}\n}"
  end

  it 'has the corpus available' do
    expect(structured_files.length).to be > 900
  end

  describe 'framework deserialization (Format adapter + from_hash)' do
    it 'round-trips every structured instance file YAML -> class -> LML instance -> class identically' do
      failures = []
      round_trips = 0

      structured_files.each do |path, rel, klass|
        original = klass.from_yaml(
          File.read(path), permitted_classes: [Date, Time]
        )
        lml_text = to_lml_instance(original, klass.name.split('::').last)
        parsed = Lutaml::Lml::Format::Adapter::StandardAdapter.parse(lml_text)
        rebuilt = klass.from_hash(parsed)
        if normalized(rebuilt.to_hash) == normalized(original.to_hash)
          round_trips += 1
        else
          failures << rel
        end
      rescue StandardError => e
        failures << "#{rel}: #{e.class}: #{e.message.lines.first.strip}"
      end

      expect(failures).to be_empty,
                          "#{failures.length} of #{structured_files.length} failed:\n  #{failures.first(10).join("\n  ")}"
      expect(round_trips).to eq(structured_files.length)
    end
  end

  describe 'ontology-typed hydration (ModelCompiler#hydrate)' do
    let(:compiler) { Ituob::Models::Compiled.compiler }

    it 'round-trips every IssueMetadata instance identically' do
      meta_files = structured_files.select { |_, rel, _| rel.end_with?('/meta.yaml') }
      failures = []
      round_trips = 0

      meta_files.each do |path, rel, _klass|
        original = Ituob::Models::IssueMetadata.from_yaml(
          File.read(path), permitted_classes: [Date, Time]
        )
        lml_text = to_lml_instance(original, 'IssueMetadata')
        doc = Lutaml::Lml.parse_document(StringIO.new(lml_text))
        hydrated = compiler.hydrate(doc)
        if normalized(hydrated.to_hash) == normalized(original.to_hash)
          round_trips += 1
        else
          failures << rel
        end
      rescue StandardError => e
        failures << "#{rel}: #{e.class}: #{e.message.lines.first.strip}"
      end

      expect(failures).to be_empty,
                          "#{failures.length} of #{meta_files.length} failed:\n  #{failures.first(10).join("\n  ")}"
      expect(round_trips).to eq(meta_files.length)
    end
  end
end
