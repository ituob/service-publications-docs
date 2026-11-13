#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Generates the JSON CLASS DESCRIPTION that drives the web editor's form
# renderer, from the LML ontology (ituob/lib/ituob/ontology/messages.lml).
#
# generate_ts_types.rb emits wire INTERFACES in which every field is
# optional and classes carry no cardinality or default; a form model needs
# those facts, so this sibling script emits them as data:
#
#   { "source": ..., "primitives": [...],
#     "enums":   { "ActionType": ["ADD", ...] },
#     "classes": { "NNPAmendment": { "attributes": [
#       { "name", "wire", "type", "kind": "primitive|class|enum",
#         "required", "collection", "default"? } ] } } }
#
# Attribute order is the ontology's declaration order. `wire` is the key in
# the stored YAML (differs from `name` only where the ontology declares a
# yaml mapping, e.g. RegisterChange register_id -> register).
#
# Output: ituob.org src/lib/form/class-description.generated.json (path
# overridable via CLASS_DESCRIPTION_PATH). Deterministic: running it twice
# yields byte-identical output.

require 'json'
require 'lutaml/lml'

ONTOLOGY_PATH = File.expand_path('../ituob/lib/ituob/ontology/messages.lml', __dir__)
OUTPUT_PATH = ENV.fetch('CLASS_DESCRIPTION_PATH') do
  File.expand_path('../../ituob.org/src/lib/form/class-description.generated.json', __dir__)
end

# Ontology scalar types. Hash/HashOrText/DateOrText are opaque to the form
# (kept exactly as stored); see src/lib/form/model.ts for their handling.
PRIMITIVES = %w[String Integer Boolean Date Float Time Hash HashOrText DateOrText].freeze

doc = Lutaml::Lml.parse_document(File.open(ONTOLOGY_PATH))
enums = doc.enums.to_h { |e| [e.name.to_s, e.attributes.map { |m| m.name.to_s }] }
class_names = doc.classes.map { |c| c.name.to_s }

classes = doc.classes.to_h do |klass|
  wire_names = klass.serialization_mappings
                    .select { |m| m.format.to_s == 'yaml' }
                    .flat_map(&:rules)
                    .to_h { |rule| [rule.field.to_s, rule.wire.to_s] }
  attrs = klass.attributes.map do |attr|
    type = attr.type.to_s
    kind = if PRIMITIVES.include?(type) then 'primitive'
           elsif enums.key?(type) then 'enum'
           elsif class_names.include?(type) then 'class'
           else raise "#{klass.name}.#{attr.name}: unknown type #{type}"
           end
    max = attr.cardinality&.max.to_s
    min = attr.cardinality&.min.to_s
    entry = {
      'name' => attr.name.to_s,
      'wire' => wire_names.fetch(attr.name.to_s, attr.name.to_s),
      'type' => type,
      'kind' => kind,
      'required' => min.to_i.positive?,
      'collection' => max.match?(/\A(\*|n)\z/) || max.to_i > 1,
    }
    default = attr.properties.find { |p| p.name.to_s == 'default' }
    entry['default'] = default.value unless default.nil?
    entry
  end
  [klass.name.to_s, { 'attributes' => attrs }]
end

File.write(OUTPUT_PATH, "#{JSON.pretty_generate('source' => 'ituob/lib/ituob/ontology/messages.lml',
                                              'primitives' => PRIMITIVES, 'enums' => enums, 'classes' => classes)}\n")
puts "wrote #{OUTPUT_PATH} (#{classes.length} classes, #{enums.length} enums)"
