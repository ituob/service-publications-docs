# frozen_string_literal: true

require 'spec_helper'
require 'lutaml/lml'
require 'stringio'

# Pending lutaml-lml release: 0.2.0's ModelCompiler#resolve_instance_value
# wraps a single nested instance in an Array even for non-collection
# attributes (its Format adapter unwraps singletons; the model compiler
# does not), and its StandardAdapter#quote_value emits dash-bearing
# strings bare, which the grammar cannot re-parse. Both are fixed in the
# lutaml-lml source, unreleased. Drop this module once a release with
# the fixes lands in ituob/Gemfile.lock.
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

  # An untyped nested instance takes the enclosing attribute's type;
  # hydrate_as_untyped would otherwise emit a raw hash polluted with a
  # `_name` key, which also defeats union member key-coverage.
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

RSpec.describe 'LML instance round-trip (YAML instance == LML instance)' do
  let(:compiler) { Ituob::Models::Compiled.compiler }

  def normalize_values(obj)
    case obj
    when Hash then obj.transform_values { |v| normalize_values(v) }
    when Array then obj.map { |v| normalize_values(v) }
    when Date, Time then obj.to_s
    else obj
    end
  end

  def normalized(obj)
    json = JSON.parse(JSON.generate(normalize_values(obj)))
    deep_compact(json)
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
  # double-quoted.
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

  def hydrate_lml(text)
    doc = Lutaml::Lml.parse_document(StringIO.new(text))
    compiler.hydrate(doc)
  end

  meta_files = Dir[File.expand_path('../../../ob-issues/*/meta.yaml', __dir__)]
    .sort

  it 'has the corpus available' do
    expect(meta_files.length).to be > 300
  end

  describe 'every IssueMetadata instance across the corpus' do
    it 'round-trips YAML -> compiled class -> LML instance -> compiled class identically' do
      round_trips = 0
      failures = []

      meta_files.each do |path|
        original = Ituob::Models::IssueMetadata.from_yaml(
          File.read(path), permitted_classes: [Date, Time]
        )
        lml_text = to_lml_instance(original, 'IssueMetadata')
        hydrated = hydrate_lml(lml_text)
        if normalized(hydrated.to_hash) == normalized(original.to_hash)
          round_trips += 1
        else
          failures << File.basename(File.dirname(path))
        end
      rescue StandardError => e
        failures << "#{File.basename(File.dirname(path))}: #{e.class}: #{e.message.lines.first.strip}"
      end

      expect(failures).to be_empty,
                          "#{failures.length} of #{meta_files.length} failed:\n  #{failures.first(10).join("\n  ")}"
      expect(round_trips).to eq(meta_files.length)
    end
  end
end
