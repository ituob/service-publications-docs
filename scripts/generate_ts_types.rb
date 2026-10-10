#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Generates TypeScript interfaces for the site's WIRE shapes from the
# LML ontology (ituob/lib/ituob/ontology/messages.lml).
#
# Output: ituob.org src/lib/schema.generated.ts (path overridable via
# SITE_TYPES_PATH). The file is committed AND regenerated in CI before
# every site build, so it can never drift from the ontology.
#
# The hand-written src/lib/types.ts remains the VIEW layer (consumer
# shapes); schema.generated.ts is the authoritative WIRE layer exactly
# as the Ruby pipeline serializes it.

require 'lutaml/lml'

ONTOLOGY_PATH = File.expand_path('../ituob/lib/ituob/ontology/messages.lml', __dir__)
OUTPUT_PATH = ENV.fetch('SITE_TYPES_PATH') do
  File.expand_path('../../ituob.org/src/lib/schema.generated.ts', __dir__)
end

TS_TYPE = {
  'String' => 'string',
  'Integer' => 'number',
  'Boolean' => 'boolean',
  'Date' => 'string', # serialized ISO date strings on the wire
  'Float' => 'number',
  'Time' => 'string',
  'Hash' => 'Record<string, unknown>', # free-form mappings (no LML primitive)
}.freeze

doc = Lutaml::Lml.parse_document(File.open(ONTOLOGY_PATH))

# Enum-typed attributes serialize as their value string on the wire
# (e.g. Registers::Change#type); there is no TS interface for an enum.
ENUM_TYPES = doc.enums.map { |e| e.name.to_s }.to_set.freeze

# Declared yaml mappings rename attributes on the wire
# (mapping yaml { map "register", to: "register_id" }).
WIRE_NAMES = doc.classes.each_with_object({}) do |klass, map|
  renames = klass.serialization_mappings
    .select { |m| m.format.to_s == "yaml" }
    .flat_map(&:rules)
    .to_h { |rule| [rule.field.to_s, rule.wire.to_s] }
  map[klass.name.to_s] = renames unless renames.empty?
end.freeze

lines = []
lines << '// GENERATED from ituob/lib/ituob/ontology/messages.lml — do not edit.'
lines << '// Regenerate: bundle exec ruby scripts/generate_ts_types.rb'
lines << '// CI regenerates this file before every site build.'
lines << ''

doc.classes.sort_by { |c| c.name.to_s }.each do |klass|
  name = klass.name.to_s
  wire_names = WIRE_NAMES.fetch(name, {})
  lines << "export interface #{name}Wire {"
  klass.attributes.each do |attr|
    raw = attr.type.to_s
    ts = if TS_TYPE.key?(raw)
           TS_TYPE[raw]
         elsif ENUM_TYPES.include?(raw)
           'string'
         else
           "#{raw}Wire"
         end
    optional = '?' # wire fields are all optional (absent when nil)
    coll = attr.cardinality&.max.to_s.match?(/(\*|n)/) || (attr.cardinality&.max.to_i.to_s == attr.cardinality&.max.to_s && attr.cardinality&.max.to_i > 1)
    ts = "#{ts}[]" if coll
    lines << "  #{wire_names.fetch(attr.name.to_s, attr.name)}#{optional}: #{ts};"
  end
  lines << '}'
  lines << ''
end

File.write(OUTPUT_PATH, lines.join("\n"))
puts "wrote #{OUTPUT_PATH} (#{doc.classes.length} interfaces)"
