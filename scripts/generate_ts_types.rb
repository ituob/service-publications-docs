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

lines = []
lines << '// GENERATED from ituob/lib/ituob/ontology/messages.lml — do not edit.'
lines << '// Regenerate: bundle exec ruby scripts/generate_ts_types.rb'
lines << '// CI regenerates this file before every site build.'
lines << ''

doc.classes.sort_by { |c| c.name.to_s }.each do |klass|
  name = klass.name.to_s
  lines << "export interface #{name}Wire {"
  klass.attributes.each do |attr|
    ts = TS_TYPE[attr.type.to_s] || "#{attr.type}Wire"
    optional = '?' # wire fields are all optional (absent when nil)
    coll = attr.cardinality&.max.to_s.match?(/(\*|n)/) || (attr.cardinality&.max.to_i.to_s == attr.cardinality&.max.to_s && attr.cardinality&.max.to_i > 1)
    ts = "#{ts}[]" if coll
    lines << "  #{attr.name}#{optional}: #{ts};"
  end
  lines << '}'
  lines << ''
end

File.write(OUTPUT_PATH, lines.join("\n"))
puts "wrote #{OUTPUT_PATH} (#{doc.classes.length} interfaces)"
