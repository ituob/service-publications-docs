#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Generates datasets/<slug>/schema-data.yaml (JSON Schema draft-07) from the
# LML Entry classes in ituob/lib/ituob/ontology/messages.lml, for the
# datasets listed in ituob/lib/ituob/ontology/data_schemas.yaml.
# The LML is the single source of the property set: never edit a generated file by hand.
# CI runs this script and fails on any diff (git diff --exit-code).
#
#   bundle exec ruby scripts/generate_data_schemas.rb

require 'lutaml/lml'
require 'yaml'

ROOT = File.expand_path(ENV.fetch('ITUOB_SCHEMA_ROOT', File.join(__dir__, '..')))
ONTOLOGY_DIR = File.join(ROOT, 'ituob/lib/ituob/ontology')
MAPPING = YAML.load_file(File.join(ONTOLOGY_DIR, 'data_schemas.yaml'))
DOC = Lutaml::Lml.parse_document(File.open(File.join(ONTOLOGY_DIR, 'messages.lml')))
CLASSES = DOC.classes.to_h { |c| [c.name.to_s, c] }.freeze

SCALAR = {
  'String' => { 'type' => 'string' },
  'Integer' => { 'type' => 'integer' },
  'Boolean' => { 'type' => 'boolean' },
  'Float' => { 'type' => 'number' },
  'Date' => { 'type' => 'string', 'format' => 'date' },
  'Hash' => { 'type' => 'object' },
}.freeze

def collection?(attr)
  max = attr.cardinality&.max
  max.to_s.match?(/(\*|n)/) || (max.to_i.to_s == max.to_s && max.to_i > 1)
end

def schema_for(type, owner)
  return SCALAR.fetch(type).dup if SCALAR.key?(type)

  klass = CLASSES[type] or abort "#{owner}: unknown type #{type}"
  object_schema(klass)
end

def object_schema(klass)
  props = klass.attributes.reject { |a| a.name.to_s == '_class' }.to_h do |attr|
    schema = schema_for(attr.type.to_s, klass.name)
    schema = { 'type' => 'array', 'items' => schema } if collection?(attr)
    [attr.name.to_s, schema]
  end
  { 'type' => 'object', 'additionalProperties' => false, 'properties' => props }
end

# Legacy constraints the LML cannot express yet (required lists, descriptions,
# formats, narrower language sets) live in ontology/data_schema_overlays/<slug>.yaml
# and are merged over the generated schema; an explicit null deletes a key.
# An overlay may only refine what the LML generated: it fails loudly when it
# names a property the LML no longer has, or uses an unknown JSON-schema keyword.
KEYWORDS = %w[type description required properties items additionalProperties format title $schema enum pattern examples].freeze

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
    if value.nil? then out.delete(name)
    else out[name] = overlay(base[name], value, "#{where}.#{name}", errors)
    end
  end
end

errors = []
overlay_dir = File.join(ONTOLOGY_DIR, 'data_schema_overlays')
Dir.glob(File.join(overlay_dir, '*.yaml')).each do |path|
  slug = File.basename(path, '.yaml')
  errors << "#{slug}: overlay file has no entry in data_schemas.yaml" unless MAPPING.key?(slug)
end

outputs = {}
MAPPING.sort.each do |slug, class_name|
  klass = CLASSES[class_name]
  dir = File.join(ROOT, 'datasets', slug)
  (errors << "#{slug}: no LML class #{class_name}"; next) unless klass
  (errors << "#{slug}: no dataset directory"; next) unless File.directory?(dir)

  title = "ITU OB Dataset Schema for #{slug.sub(/\A\d+-/, '')} (generated from LML #{class_name})"
  schema = {
    '$schema' => 'http://json-schema.org/draft-07/schema#',
    'title' => title,
    'type' => 'array',
    'items' => object_schema(klass),
  }
  overlay_path = File.join(overlay_dir, "#{slug}.yaml")
  if File.file?(overlay_path)
    patch = YAML.load_file(overlay_path)
    schema = overlay(schema, patch, slug, errors)
  end
  header = "# GENERATED from ituob/lib/ituob/ontology/messages.lml (#{class_name}) - do not edit.\n" \
           "# Regenerate: BUNDLE_GEMFILE=ituob/Gemfile bundle exec ruby scripts/generate_data_schemas.rb\n"
  outputs[File.join(dir, 'schema-data.yaml')] = header + YAML.dump(schema)
end

unless errors.empty?
  warn "generate_data_schemas: #{errors.size} error(s); nothing was written:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
end

outputs.each do |path, body|
  File.write(path, body)
  puts "wrote #{path.delete_prefix("#{ROOT}/")}"
end
