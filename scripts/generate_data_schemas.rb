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

ROOT = File.expand_path('..', __dir__)
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
# and are deep-merged over the generated schema; an explicit null deletes a key.
def overlay(base, patch)
  return patch unless base.is_a?(Hash) && patch.is_a?(Hash)

  patch.each_with_object(base.dup) do |(key, value), out|
    if value.nil? then out.delete(key)
    else out[key] = overlay(base[key], value)
    end
  end
end

MAPPING.sort.each do |slug, class_name|
  klass = CLASSES[class_name] or abort "#{slug}: no LML class #{class_name}"
  dir = File.join(ROOT, 'datasets', slug)
  abort "#{slug}: no dataset directory" unless File.directory?(dir)

  title = "ITU OB Dataset Schema for #{slug.sub(/\A\d+-/, '')} (generated from LML #{class_name})"
  schema = {
    '$schema' => 'http://json-schema.org/draft-07/schema#',
    'title' => title,
    'type' => 'array',
    'items' => object_schema(klass),
  }
  overlay_path = File.join(ONTOLOGY_DIR, 'data_schema_overlays', "#{slug}.yaml")
  schema = overlay(schema, YAML.load_file(overlay_path)) if File.file?(overlay_path)
  header = "# GENERATED from ituob/lib/ituob/ontology/messages.lml (#{class_name}) - do not edit.\n" \
           "# Regenerate: BUNDLE_GEMFILE=ituob/Gemfile bundle exec ruby scripts/generate_data_schemas.rb\n"
  File.write(File.join(dir, 'schema-data.yaml'), header + YAML.dump(schema))
  puts "wrote datasets/#{slug}/schema-data.yaml"
end
