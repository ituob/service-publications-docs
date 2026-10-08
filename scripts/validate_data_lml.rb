#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Instance-data gate: loads every ob-issues YAML file through the
# compiled-from-LML classes, so the corpus is provably valid against
# the ontology-defined shapes.
#
#   bundle exec ruby scripts/validate_data_lml.rb [--all]
#
# Default validates a deterministic sample (first + last issue of each
# decade); --all walks the full corpus. Exits 1 on any failure.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'yaml'

ALL = ARGV.include?('--all')
ROOT = File.expand_path('../ob-issues', __dir__)

# Class resolution per file path within an issue tree.
def class_for(rel_path)
  case rel_path
  when /\Ameta\.yaml\z/ then 'IssueMetadata'
  when /\Aannexes\.yaml\z/ then nil # freeform annex snapshot (legacy)
  when %r{\Ageneral/} then nil # general messages: mixed structured/freeform
  when %r{\A([^/]+)/text\.yaml\z} then 'TextAmendment'
  when %r{\A([^/]+)/(\d+[a-z0-9.\-]*)\.yaml\z} then amendment_class_for($1)
  end
end

# ob-issues dataset directory slug -> amendment class. General-message
# directories map to their structured general classes; the remaining
# text-by-design datasets (list-v, coast-stations, bureaufax, rr251,
# e212-icc) resolve to TextAmendment via their text.yaml files.
CLASS_BY_DIR = {
  # amendments
  'dp' => 'DPAmendment', 'e118-iin' => 'E118Amendment', 'e164-acn' => 'E164ACNAmendment',
  'e164-cc' => 'E164CCAmendment', 'e212-mnc' => 'E212MNCAmendment', 'e218-trcc' => 'E218TRCCAmendment',
  'f32-tdi' => 'F32TDIAmendment', 'f400-admd' => 'F400Amendment', 'list-viii' => 'ListVIIIAmendment',
  'm1400-icc' => 'M1400Amendment', 'nnp' => 'NNPAmendment', 'q708-ispc' => 'Q708ISPCAmendment',
  'q708-sanc' => 'Q708SANCAmendment', 't35-na' => 'T35NAAmendment', 'x121-dnic' => 'X121DNICAmendment',
  # structured general messages
  'callback-procedures' => 'GeneralCallbackProcedures', 'custom' => 'GeneralCustom',
  'ipns' => 'GeneralIpns', 'iptn' => 'GeneralIptn', 'misc-communications' => 'GeneralMiscCommunications',
  'sanc' => 'GeneralSanc', 'service-restrictions' => 'GeneralServiceRestrictions',
  'telephone-service-2' => 'GeneralTelephoneService', 'telephone-service' => 'GeneralTelephoneService',
}.freeze

def amendment_class_for(dir)
  CLASS_BY_DIR.fetch(dir, nil)
end

issues = Dir.children(ROOT).grep(/\A\d+\z/).map(&:to_i).sort
selected = ALL ? issues : issues.select { |i| (i % 10).zero? || i == issues.min || i == issues.max }
selected -= [669, 1075] if selected.include?(669) && !ALL # incomplete editions validated separately

failures = []
validated = 0
skipped = 0

selected.each do |issue|
  dir = File.join(ROOT, issue.to_s)
  Dir.glob(File.join(dir, '**', '*.yaml')).sort.each do |path|
    rel = path.delete_prefix("#{dir}/")
    cls_name = class_for(rel)
    if cls_name.nil?
      skipped += 1
      next
    end
    data = YAML.load_file(path, permitted_classes: [Date, Time])
    # Trust the serialized _class when present (text fallbacks record
    # the originating amendment class); path heuristic otherwise.
    resolved = data.is_a?(Hash) && data['_class'] ? data['_class'] : cls_name
    unless resolved && Ituob::Models.const_defined?(resolved)
      failures << "#{issue}/#{rel}: cannot resolve class #{resolved.inspect}"
      next
    end
    Ituob::Models.const_get(resolved).from_yaml(data.to_yaml, permitted_classes: [Date, Time])
    validated += 1
  rescue StandardError => e
    failures << "#{issue}/#{rel} [#{cls_name}]: #{e.class}: #{e.message.lines.first.strip}"
  end
end

puts "issues checked: #{selected.length}; files validated: #{validated}; skipped (freeform): #{skipped}"
if failures.empty?
  puts 'INSTANCE DATA VALID'
  exit 0
else
  puts "FAILURES: #{failures.length}"
  failures.first(25).each { |f| puts "  #{f}" }
  exit 1
end
