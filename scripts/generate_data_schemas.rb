#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Generates datasets/<slug>/schema-data.yaml (JSON Schema draft-07) from the
# LML Entry classes in ituob/lib/ituob/ontology/messages.lml, for the
# datasets listed in ituob/lib/ituob/ontology/data_schemas.yaml, and the
# other data schemas (change files, dataset metadata, catalogs, the RR.25.1
# country list) listed in ituob/lib/ituob/ontology/document_schemas.yaml.
# The LML is the single source of the property set: never edit a generated file by hand.
# CI uses --verify to reject incomplete, untracked or outdated schemas without writing.
#
#   bundle exec ruby scripts/generate_data_schemas.rb

require 'lutaml/lml'
require 'yaml'
require 'json-schema'
require 'json'
require 'open3'

VERIFY = ARGV.delete('--verify')
abort "Usage: #{$PROGRAM_NAME} [--verify]" unless ARGV.empty?

ROOT = File.expand_path(ENV.fetch('ITUOB_SCHEMA_ROOT', File.join(__dir__, '..')))
ONTOLOGY_DIR = File.join(ROOT, 'ituob/lib/ituob/ontology')
MAPPING = YAML.load_file(File.join(ONTOLOGY_DIR, 'data_schemas.yaml'))
DOCUMENTS_PATH = File.join(ONTOLOGY_DIR, 'document_schemas.yaml')
DOCUMENTS = File.file?(DOCUMENTS_PATH) ? YAML.load_file(DOCUMENTS_PATH) : {}
DOC = Lutaml::Lml.parse_document(File.open(File.join(ONTOLOGY_DIR, 'messages.lml')))
CLASSES = DOC.classes.to_h { |c| [c.name.to_s, c] }.freeze
ENUMS = DOC.enums.to_h { |e| [e.name.to_s, e.attributes.map { |m| m.name.to_s }] }.freeze

SCALAR = {
  'String' => { 'type' => 'string' },
  'Integer' => { 'type' => 'integer' },
  'Boolean' => { 'type' => 'boolean' },
  'Float' => { 'type' => 'number' },
  'Date' => { 'type' => 'string', 'format' => 'date' },
  'Hash' => { 'type' => 'object' },
  'NullableString' => { 'type' => ['string', 'null'] },
  'StringOrNumber' => { 'type' => ['number', 'string'] },
  'StringOrObject' => { 'type' => ['string', 'object'] },
  'HashOrList' => { 'type' => ['array', 'object'] },
}.freeze

def collection?(attr)
  max = attr.cardinality&.max
  max.to_s.match?(/(\*|n)/) || (max.to_i.to_s == max.to_s && max.to_i > 1)
end

def schema_for(type, owner, path, ancestors)
  return SCALAR.fetch(type).dup if SCALAR.key?(type)
  return { 'type' => 'string', 'enum' => ENUMS.fetch(type) } if ENUMS.key?(type)

  klass = CLASSES[type] or abort "#{owner}: unknown type #{type}"
  return { '$ref' => ancestors[type] } if ancestors.key?(type)

  object_schema(klass, path, ancestors)
end

# Attributes whose file key differs from the attribute name (`mapping yaml`).
def wire_names(klass)
  Array(klass.serialization_mappings).flat_map(&:rules).to_h { |rule| [rule.field.to_s, rule.wire.to_s] }
end

def object_schema(klass, path = '#/items', ancestors = {})
  ancestors = ancestors.merge(klass.name.to_s => path)
  wire = wire_names(klass)
  props = Array(klass.attributes).reject { |a| a.name.to_s == '_class' }.to_h do |attr|
    name = wire.fetch(attr.name.to_s, attr.name.to_s)
    child_path = "#{path}/properties/#{name}"
    child_path += '/items' if collection?(attr)
    schema = schema_for(attr.type.to_s, klass.name, child_path, ancestors)
    schema = { 'type' => 'array', 'items' => schema } if collection?(attr)
    [name, schema]
  end
  { 'type' => 'object', 'additionalProperties' => false, 'properties' => props }
end

# Constraints and descriptions live in ontology/data_schema_overlays/<slug>.yaml.
# Overlays cannot replace or remove the structure derived from the LML.
# An overlay may only refine what the LML generated: it fails loudly when it
# names a property the LML no longer has, or uses an unknown JSON-schema keyword.
# Vendored from https://json-schema.org/draft-07/schema, so generation is offline.
METASCHEMA = JSON.parse(File.read(File.join(__dir__, 'schemas/draft-07.json')))
# json-schema 3 supports draft6, which implements every assertion used by the
# draft7 metaschema. Pass a Hash to avoid its obsolete JSON.parse quirks_mode.
METASCHEMA.delete('$schema')
METASCHEMA.delete('$id')
# The gem cannot instantiate the metaschema's boolean subschemas (const, default
# and examples accept anything); the empty schema means the same.
METASCHEMA['properties'].transform_values! { |schema| schema == true ? {} : schema }
# References replace sibling assertions in draft7, so an overlay reference could
# bypass the model type even without a literal type override.
KEYWORDS = %w[oneOf allOf not if then else const default type description required properties items additionalProperties format title enum pattern examples
              minimum maximum exclusiveMinimum exclusiveMaximum multipleOf minLength maxLength
              minItems maxItems uniqueItems minProperties maxProperties].freeze

def validate_schema(schema, where, errors)
  JSON::Validator.fully_validate(METASCHEMA, schema, version: :draft6).each do |error|
    errors << "#{where}: invalid JSON Schema: #{error}"
  end
end

def validate_references(schema, where, errors)
  return unless schema.is_a?(Hash)

  if schema['required'].is_a?(Array) && schema['properties'].is_a?(Hash)
    (schema['required'] - schema['properties'].keys).each do |name|
      errors << "#{where}: required property #{name.inspect} is not in the final properties"
    end
  end
  if schema['pattern'].is_a?(String)
    begin
      Regexp.new(schema['pattern'])
    rescue RegexpError => e
      errors << "#{where}: invalid pattern: #{e.message}"
    end
  end
  schema.fetch('properties', {}).each do |name, child|
    validate_references(child, "#{where}.properties.#{name}", errors)
  end if schema['properties'].is_a?(Hash)
  validate_references(schema['items'], "#{where}.items", errors)
end

def overlay(base, patch, where, errors)
  unless patch.is_a?(Hash)
    errors << "#{where}: overlay node must be a mapping"
    return base
  end

  base ||= {}
  patch.each_with_object(base.dup) do |(key, value), out|
    unless KEYWORDS.include?(key)
      errors << "#{where}: unknown overlay key #{key.inspect}"
      next
    end
    if base.key?(key) && %w[type items properties additionalProperties].include?(key) &&
        (value.nil? || (key == 'type' && value != base[key]) ||
          (key == 'additionalProperties' && base[key] == false && value != false))
      errors << "#{where}.#{key}: cannot change or remove LML-generated #{key}"
      next
    end
    if value.nil? then out.delete(key)
    elsif key == 'properties' then out[key] = overlay_properties(base[key], value, "#{where}.properties", errors)
    elsif key == 'items' && base[key].is_a?(Hash) then out[key] = overlay(base[key], value, "#{where}.items", errors)
    else out[key] = value
    end
  end
end

def overlay_properties(base, patch, where, errors)
  # A Hash-typed LML attribute has no properties of its own: the overlay
  # describes its shape. Where the LML does define properties it is binding.
  free_shape = base.nil?
  base ||= {}
  return (errors << "#{where}: must be a mapping"; base) unless patch.is_a?(Hash)

  patch.each_with_object(base.dup) do |(name, value), out|
    unless free_shape || base.key?(name)
      errors << "#{where}.#{name}: not in the LML-generated schema (dropped from the LML?)"
      next
    end
    if value.nil?
      errors << "#{where}.#{name}: cannot remove an LML-generated property"
    else
      out[name] = overlay(base[name], value, "#{where}.#{name}", errors)
    end
  end
end

# One schema to emit: a dataset seed schema (array of entries) or a document
# schema listed in document_schemas.yaml (an array of rows, or one object).
Target = Struct.new(:name, :class_name, :path, :root, :id, :title)

def dataset_targets
  MAPPING.sort.map do |slug, class_name|
    title = "ITU OB Dataset Schema for #{slug.sub(/\A\d+-/, '')} (generated from LML #{class_name})"
    Target.new(slug, class_name, File.join('datasets', slug, 'schema-data.yaml'), 'array', nil, title)
  end
end

def document_targets
  DOCUMENTS.sort.map do |name, spec|
    Target.new(name, spec['model'], spec['path'], spec['root'], spec['id'], spec['title'])
  end
end

def build_schema(target, klass)
  schema = { '$schema' => 'http://json-schema.org/draft-07/schema#' }
  schema['$id'] = target.id if target.id
  schema.merge!('title' => target.title, 'x-lml-model' => target.class_name)
  if target.root == 'object'
    schema.merge(object_schema(klass, '#'))
  else
    schema.merge('type' => 'array', 'items' => object_schema(klass))
  end
end

errors = []
targets = dataset_targets + document_targets
(targets.map(&:name) - targets.map(&:name).uniq).each { |n| errors << "#{n}: listed more than once" }
document_targets.each do |t|
  errors << "#{t.name}: root must be array or object" unless %w[array object].include?(t.root)
  errors << "#{t.name}: document schema needs a title" unless t.title
end
# Coverage is checked before writes in both modes: a new schema must be mapped.
Dir.glob(File.join(ROOT, 'datasets/*/{schema-data,data}.yaml')).each do |path|
  slug = File.basename(File.dirname(path))
  errors << "#{slug}: schema-data.yaml has no entry in data_schemas.yaml" unless MAPPING.key?(slug)
end
if VERIFY
  tracked, error, status = Open3.capture3('git', 'ls-files', '--', 'datasets', chdir: ROOT)
  if status.success?
    tracked = tracked.lines.map(&:strip)
    Dir.glob(File.join(ROOT, 'datasets/*/schema-data.yaml')).each do |path|
      relative = path.delete_prefix("#{ROOT}/")
      errors << "#{relative}: schema is not tracked by git" unless tracked.include?(relative)
    end
    document_targets.each do |t|
      errors << "#{t.path}: schema is not tracked by git" unless tracked.include?(t.path)
    end
  else
    errors << "cannot verify tracked schemas: #{error.strip}"
  end
end
overlay_dir = File.join(ONTOLOGY_DIR, 'data_schema_overlays')
Dir.glob(File.join(overlay_dir, '*.yaml')).each do |path|
  name = File.basename(path, '.yaml')
  unless targets.any? { |t| t.name == name }
    errors << "#{name}: overlay file has no entry in data_schemas.yaml or document_schemas.yaml"
  end
end

outputs = {}
targets.each do |target|
  slug = target.name
  klass = CLASSES[target.class_name]
  dir = File.dirname(File.join(ROOT, target.path))
  (errors << "#{slug}: no LML class #{target.class_name}"; next) unless klass
  (errors << "#{slug}: no dataset directory"; next) unless File.directory?(dir)

  schema = build_schema(target, klass)
  overlay_path = File.join(overlay_dir, "#{slug}.yaml")
  if File.file?(overlay_path)
    patch = YAML.load_file(overlay_path)
    validate_schema(patch, "#{slug} overlay", errors) if patch.is_a?(Hash)
    schema = overlay(schema, patch, slug, errors)
  end
  validate_schema(schema, slug, errors)
  validate_references(schema, slug, errors)
  header = "# GENERATED from ituob/lib/ituob/ontology/messages.lml (#{target.class_name}) - do not edit.\n" \
           "# Regenerate: BUNDLE_GEMFILE=ituob/Gemfile bundle exec ruby scripts/generate_data_schemas.rb\n"
  path = File.join(ROOT, target.path)
  outputs[path] = header + YAML.dump(schema)
  if VERIFY && (!File.file?(path) || File.binread(path) != outputs[path].b)
    errors << "#{slug}: #{File.basename(path)} is missing or outdated; regenerate schemas"
  end
end

unless errors.empty?
  warn "generate_data_schemas: #{errors.size} error(s); nothing was written:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
end

if VERIFY
  puts "Verified #{outputs.size} generated data schemas"
  exit 0
end

outputs.each do |path, body|
  File.write(path, body)
  puts "wrote #{path.delete_prefix("#{ROOT}/")}"
end
