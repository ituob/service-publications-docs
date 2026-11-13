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
# A second output, schema.validators.generated.ts (SITE_VALIDATORS_PATH,
# default: beside the types file), carries RUNTIME validators from the
# same ontology for the Worker's submit-time validation: per class the
# wire keys, scalar kinds, collections, enum members and required
# attributes, plus a small interpreter. Both outputs are deterministic
# (classes and enums sorted, fixed key order), so a CI diff check is exact.
#
# The hand-written src/lib/types.ts remains the VIEW layer (consumer
# shapes); schema.generated.ts is the authoritative WIRE layer exactly
# as the Ruby pipeline serializes it.

require 'lutaml/lml'

ONTOLOGY_PATH = File.expand_path('../ituob/lib/ituob/ontology/messages.lml', __dir__)
OUTPUT_PATH = ENV.fetch('SITE_TYPES_PATH') do
  File.expand_path('../../ituob.org/src/lib/schema.generated.ts', __dir__)
end

VALIDATORS_PATH = ENV.fetch('SITE_VALIDATORS_PATH') do
  File.join(File.dirname(OUTPUT_PATH), 'schema.validators.generated.ts')
end

TS_TYPE = {
  'String' => 'string',
  'Integer' => 'number',
  'Boolean' => 'boolean',
  'Date' => 'string', # serialized ISO date strings on the wire
  'Float' => 'number',
  'Time' => 'string',
  'Hash' => 'Record<string, unknown>', # free-form mappings (no LML primitive)
  'HashOrText' => 'Record<string, unknown> | string', # mapping, or a string kept as stored
  'DateOrText' => 'string', # date or timestamp as ISO text, or free text; kept as stored
}.freeze

VALIDATOR_RUNTIME_HEADER = <<~'TS'
  export type FieldKind =
    | "string" | "integer" | "float" | "boolean" | "date" | "time"
    | "hash" | "hashOrText" | "dateOrText" | "enum" | "class";

  export interface FieldSpec {
    kind: FieldKind;
    /** Enum or class name when kind is "enum" or "class". */
    ref?: string;
    many?: true;
    required?: true;
  }

  export interface SchemaIssue {
    path: string;
    code: "required" | "type" | "enum" | "unknown";
    message: string;
  }

TS

VALIDATOR_RUNTIME_BODY = <<~'TS'
  const isObj = (v: unknown): v is Record<string, unknown> =>
    v !== null && typeof v === "object" && !Array.isArray(v);

  const KIND_LABEL: Record<string, string> = {
    string: "a string", integer: "an integer", float: "a number", boolean: "a boolean",
    date: "an ISO date string (YYYY-MM-DD)", time: "a timestamp string", hash: "an object",
    hashOrText: "an object or a string", dateOrText: "a string", enum: "an enum member", class: "an object",
  };

  function scalarOk(kind: FieldKind, v: unknown): boolean {
    switch (kind) {
      case "string": return typeof v === "string";
      case "integer": return (typeof v === "number" && Number.isInteger(v)) || (typeof v === "string" && /^-?\d+$/.test(v));
      case "float": return (typeof v === "number" && Number.isFinite(v)) || (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v)));
      case "boolean": return typeof v === "boolean";
      case "date": return typeof v === "string" && /^\d{4}-\d{2}-\d{2}/.test(v);
      case "time": return typeof v === "string";
      case "hash": return isObj(v);
      case "hashOrText": return isObj(v) || typeof v === "string";
      case "dateOrText": return typeof v === "string";
      default: return false;
    }
  }

  function checkValue(spec: FieldSpec, v: unknown, path: string, out: SchemaIssue[]): void {
    if (spec.kind === "enum") {
      const members = ENUMS[spec.ref as string] ?? [];
      if (typeof v !== "string" || !members.includes(v))
        out.push({ path, code: "enum", message: `${path} must be one of ${members.join(", ")}` });
    } else if (spec.kind === "class") {
      out.push(...validateClass(spec.ref as string, v, path));
    } else if (!scalarOk(spec.kind, v)) {
      out.push({ path, code: "type", message: `${path} must be ${KIND_LABEL[spec.kind]}` });
    }
  }

  /**
   * Validate `value` against the ontology class `name`. Unknown keys are
   * rejected (the Ruby gate rejects them too); null/absent optional keys pass.
   */
  export function validateClass(name: string, value: unknown, path = ""): SchemaIssue[] {
    const fields = CLASSES[name];
    const at = path === "" ? "(root)" : path;
    if (!fields) return [{ path, code: "unknown", message: `unknown class ${name}` }];
    if (!isObj(value)) return [{ path, code: "type", message: `${at} must be an object (${name})` }];
    const out: SchemaIssue[] = [];
    const sub = (k: string) => (path === "" ? k : `${path}.${k}`);
    for (const k of Object.keys(value)) {
      if (!Object.prototype.hasOwnProperty.call(fields, k))
        out.push({ path: sub(k), code: "unknown", message: `${sub(k)} is not an attribute of ${name}` });
    }
    for (const [k, spec] of Object.entries(fields)) {
      const v = value[k];
      if (v === undefined || v === null) {
        if (spec.required) out.push({ path: sub(k), code: "required", message: `${sub(k)} is required` });
        continue;
      }
      if (spec.many) {
        if (!Array.isArray(v)) {
          out.push({ path: sub(k), code: "type", message: `${sub(k)} must be a list` });
          continue;
        }
        v.forEach((item, i) => checkValue(spec, item, `${sub(k)}[${i}]`, out));
      } else {
        checkValue(spec, v, sub(k), out);
      }
    }
    return out;
  }

  /** Class names usable as a register amendment payload (`data._class`). */
  export const AMENDMENT_CLASSES: readonly string[] = Object.keys(CLASSES).filter(
    (n) => n.endsWith("Amendment") && n !== "Amendment",
  );
TS

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

# Whether an attribute is a collection (cardinality max is `n`, `*` or > 1).
def collection?(attr)
  max = attr.cardinality&.max
  max.to_s.match?(/(\*|n)/) || (max.to_i.to_s == max.to_s && max.to_i > 1)
end

# An attribute is required when its cardinality minimum is >= 1
# (`cardinality 1`); everything else is optional on the wire.
def required?(attr)
  attr.cardinality&.min.to_i >= 1
end

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
    ts = "#{ts}[]" if collection?(attr)
    lines << "  #{wire_names.fetch(attr.name.to_s, attr.name)}#{optional}: #{ts};"
  end
  lines << '}'
  lines << ''
end

File.write(OUTPUT_PATH, lines.join("\n"))
puts "wrote #{OUTPUT_PATH} (#{doc.classes.length} interfaces)"

# ---- runtime validators ---------------------------------------------

VALIDATOR_KIND = {
  'String' => 'string', 'Integer' => 'integer', 'Float' => 'float', 'Boolean' => 'boolean',
  'Date' => 'date', 'Time' => 'time', 'Hash' => 'hash', 'HashOrText' => 'hashOrText',
  'DateOrText' => 'dateOrText'
}.freeze

class_names = doc.classes.map { |c| c.name.to_s }.to_set

def ts_string(str) = str.to_s.inspect

specs = doc.classes.sort_by { |c| c.name.to_s }.map do |klass|
  name = klass.name.to_s
  wire_names = WIRE_NAMES.fetch(name, {})
  fields = klass.attributes.map do |attr|
    raw = attr.type.to_s
    kind, ref =
      if VALIDATOR_KIND.key?(raw) then [VALIDATOR_KIND[raw], nil]
      elsif ENUM_TYPES.include?(raw) then ['enum', raw]
      elsif class_names.include?(raw) then ['class', raw]
      else abort "generate_ts_types: unknown attribute type #{raw} on #{name}.#{attr.name}"
      end
    parts = ["kind: #{ts_string(kind)}"]
    parts << "ref: #{ts_string(ref)}" if ref
    parts << 'many: true' if collection?(attr)
    parts << 'required: true' if required?(attr)
    "    #{ts_string(wire_names.fetch(attr.name.to_s, attr.name.to_s))}: { #{parts.join(', ')} },"
  end
  ["  #{ts_string(name)}: {", *fields, '  },'].join("\n")
end

enums = doc.enums.sort_by { |e| e.name.to_s }.map do |e|
  "  #{ts_string(e.name)}: [#{e.attributes.map { |m| ts_string(m.name) }.join(', ')}],"
end

vlines = []
vlines << '// GENERATED from ituob/lib/ituob/ontology/messages.lml — do not edit.'
vlines << '// Regenerate: bundle exec ruby scripts/generate_ts_types.rb'
vlines << '// Runtime validators for the Worker; CI regenerates and diff-checks this file.'
vlines << '// Erasable TypeScript only (runs under node --experimental-strip-types).'
vlines << ''
vlines << VALIDATOR_RUNTIME_HEADER
vlines << 'export const ENUMS: Readonly<Record<string, readonly string[]>> = {'
vlines.concat(enums)
vlines << '};'
vlines << ''
vlines << 'export const CLASSES: Readonly<Record<string, Readonly<Record<string, FieldSpec>>>> = {'
vlines.concat(specs)
vlines << '};'
vlines << ''
vlines << VALIDATOR_RUNTIME_BODY

File.write(VALIDATORS_PATH, vlines.join("\n"))
puts "wrote #{VALIDATORS_PATH} (#{doc.classes.length} class validators, #{doc.enums.length} enums)"
