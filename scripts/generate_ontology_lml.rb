#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Generates ituob/ontology/messages.lml from the LIVE model classes
# (dump_model_inventory.rb). The .lml is thereafter hand-maintained
# source; the ontology_spec drift guard fails when the Ruby classes
# and the .lml disagree, so regeneration is only for bulk edits —
# review the diff like any source change.

require 'json'

inventory = JSON.parse(File.read(File.expand_path('output/model_inventory.json', __dir__)))
out_path = File.expand_path('../ituob/lib/ituob/ontology/messages.lml', __dir__)

FAMILY_ORDER = [
  ['Shared value types', %w[MultilingualString]],
  ['Shared bases', %w[Entry Amendment GeneralMessage Change ChangeSet]],
  ['Issue-level', %w[IssueContact IssueAuthor IssueMetadata IssueGeneral OldIssue]],
  ['E.118 (Issuer Identification Numbers)', nil],
  ['E.164 family', nil],
  ['E.212 family', nil],
  ['E.218', nil],
  ['F.32', nil],
  ['F.400', nil],
  ['List VIII (coast/monitoring stations)', nil],
  ['M.1400', nil],
  ['NNP (national numbering plans)', nil],
  ['DP (dialling procedures)', nil],
  ['Q.708 family', nil],
  ['RR 25.1', nil],
  ['T.35 family', nil],
  ['X.121', nil],
  ['General message types', nil],
  ['Textual fallbacks', nil],
].freeze

LML_TYPE = {
  'String' => 'String',
  'Integer' => 'Integer',
  'Boolean' => 'Boolean',
  'Date' => 'Date',
  'Hash' => 'Hash',
}.freeze

# lml renders type names as declared; class-ref types use the class name.
def lml_type(type)
  LML_TYPE.fetch(type, type)
end

sorted_names = inventory.keys.sort
family_of = Hash.new { |h, k| h[k] = 'Other' }
FAMILY_ORDER.each do |label, members|
  next unless members

  members.each { |m| family_of[m] = label }
end
# Assign unlisted classes by prefix convention
prefix_rules = {
  /\AE118/ => 'E.118 (Issuer Identification Numbers)',
  /\AE164/ => 'E.164 family',
  /\AE212/ => 'E.212 family',
  /\AE218/ => 'E.218',
  /\AF32TDI/ => 'F.32',
  /\AF400/ => 'F.400',
  /\AListVIII/ => 'List VIII (coast/monitoring stations)',
  /\AM1400/ => 'M.1400',
  /\ANNP|NumberingPlan/ => 'NNP (national numbering plans)',
  /\ADP/ => 'DP (dialling procedures)',
  /\AQ708/ => 'Q.708 family',
  /\ARR251/ => 'RR 25.1',
  /\AT35/ => 'T.35 family',
  /\AX121/ => 'X.121',
  /\AGeneral/ => 'General message types',
  /\AText/ => 'Textual fallbacks',
}
sorted_names.each do |n|
  next unless family_of[n] == 'Other'

  prefix_rules.each { |re, label| break family_of[n] = label if n.match?(re) }
end

lines = []
lines << '// ITU Operational Bulletin — message and dataset model ontology.'
lines << '//'
lines << '// Single declarative source for the data shapes of the ituob gem'
lines << '// (Ituob::Models::*). The Ruby classes are the executable truth;'
lines << '// this ontology is the authoritative schema documentation and the'
lines << '// source for compiled classes (ListVIII family) and the generated'
lines << '// TypeScript interfaces on the Astro site.'
lines << '//'
lines << '// Enforced by ituob/spec/ituob/ontology_spec.rb: attributes,'
lines << '// cardinality and types must match the Ruby classes exactly.'
lines << '//'
lines << '// Regenerate (bulk edits only, review the diff):'
lines << '//   bundle exec ruby scripts/dump_model_inventory.rb scripts/output/model_inventory.json'
lines << '//   bundle exec ruby scripts/generate_ontology_lml.rb'
lines << ''
lines << 'models Ituob {'

grouped = sorted_names.group_by { |n| family_of[n] }
emitted = []
FAMILY_ORDER.map(&:first).concat(['Other']).each do |label|
  group = grouped[label]
  next unless group && !group.empty?

  lines << ''
  lines << "  // #{label}"
  group.sort.each do |name|
    rec = inventory[name]
    lines << ''
    lines << "  class #{name} {"
    rec['attributes'].each do |attr, meta|
      parts = ["attribute #{attr}, #{lml_type(meta['type'])}"]
      mods = []
      mods << 'cardinality 0..n' if meta['collection']
      if attr == '_class'
        mods << "default: \"#{name}\""
      elsif meta['default'] && meta['default'] != 'nil'
        lit = meta['default'].gsub(/\A"(.*)"\z/, '\1')
        mods << "default: \"#{lit}\"" unless lit.empty?
      end
      if mods.empty?
        lines << "    #{parts[0]}"
      else
        lines << "    #{parts[0]} { #{mods.join('; ')} }"
      end
    end
    lines << '  }'
    emitted << name
  end
end

lines << '}'

File.write(out_path, lines.join("\n") + "\n")
puts "wrote #{out_path} (#{emitted.length} classes)"
