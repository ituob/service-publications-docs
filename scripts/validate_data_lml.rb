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

def deep_stringify_keys(value)
  case value
  when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify_keys(v) }
  when Array then value.map { |v| deep_stringify_keys(v) }
  else value
  end
end

def freeform_general_message?(rel, data)
  resolved = Ituob::Support::CorpusTree.resolve_for(rel, data)
  resolved&.start_with?('General') && data.is_a?(Hash) && data['contents'].is_a?(String)
end

issues = Dir.children(ROOT).grep(/\A\d+\z/).map(&:to_i).sort
selected = ALL ? issues : issues.select { |i| (i % 10).zero? || i == issues.min || i == issues.max }
selected -= [669, 1075] if selected.include?(669) && !ALL # incomplete editions validated separately

failures = []
validated = 0
skipped = 0

# Check the complete inventory even when validating a sample of issues.
freeform_messages = YAML.load_file(File.expand_path('../catalogs/freeform_messages.yaml', __dir__))
freeform_by_file = {}
freeform_messages.each do |entry|
  file = entry.fetch('file')
  asset = entry.fetch('source_asset')
  reason = entry.fetch('reason')
  failures << "#{file}: duplicate freeform listing" if freeform_by_file.key?(file)
  failures << "#{file}: missing freeform reason" if reason.to_s.strip.empty?
  freeform_by_file[file] = entry
  path = File.join(ROOT, file)
  unless File.file?(path)
    failures << "#{file}: listed message is missing"
    next
  end

  data = YAML.load_file(path, permitted_classes: [Date, Time], aliases: true)
  unless freeform_general_message?(file.split('/', 2).last, data)
    failures << "#{file}: listed message is no longer freeform"
  end
  unless File.file?(File.expand_path(asset, File.expand_path('..', __dir__)))
    failures << "#{file}: missing source asset #{asset}"
  end
rescue StandardError => e
  failures << "#{file}: #{e.class}: #{e.message.lines.first.strip}"
end

selected.each do |issue|
  dir = File.join(ROOT, issue.to_s)
  Dir.glob(File.join(dir, '**', '*.yaml')).sort.each do |path|
    rel = path.delete_prefix("#{dir}/")
    # Freeform positions are skipped before reading: their payloads may
    # contain YAML aliases the strict loader rejects.
    if Ituob::Support::CorpusTree.class_name_for(rel).nil?
      # Legacy annex snapshots have one modeled shape: a map of
      # publication id -> { position_on: date, datasets? }. Anything
      # else in them is a defect.
      if rel.end_with?('annexes.yaml')
        data = YAML.load_file(path, permitted_classes: [Date, Time], aliases: true)
        unless data.is_a?(Hash) && data.all? do |pub, v|
          v.nil? || (v.is_a?(Hash) &&
                     (v.keys - ['position_on', 'datasets']).empty? &&
                     (v['position_on'].nil? || v['position_on'].is_a?(Date) || v['position_on'].is_a?(Time)))
        end
          failures << "#{issue}/#{rel}: malformed annex snapshot"
        end
        validated += 1
      else
        skipped += 1
      end
      next
    end

    data = YAML.load_file(path, permitted_classes: [Date, Time], aliases: true)
    resolved = Ituob::Support::CorpusTree.resolve_for(rel, data)
    if resolved.nil?
      skipped += 1
      next
    end
    if freeform_general_message?(rel, data)
      file = "#{issue}/#{rel}"
      entry = freeform_by_file[file]
      if entry
        puts "SKIP #{file}: #{entry.fetch('reason')} (source: #{entry.fetch('source_asset')})"
        skipped += 1
      else
        failures << "#{file}: unlisted freeform general message"
      end
      next
    end
    if resolved == 'RegisterChange'
      # Amendment file: the envelope validates through Registers::Change
      # and the data payload through the amendment class its _class
      # names. Unknown payload keys fail — the classes declare the
      # corpus shapes completely.
      Ituob::Registers::Change.from_hash(data)
      payload_name = data.dig('data', '_class')
      unless payload_name && Ituob::Models.const_defined?(payload_name)
        failures << "#{issue}/#{rel}: cannot resolve payload class #{payload_name.inspect}"
        next
      end
      payload_class = Ituob::Models.const_get(payload_name)
      payload = data['data']
      unknown = payload.keys - payload_class.attributes.keys.map(&:to_s)
      unless unknown.empty?
        failures << "#{issue}/#{rel}: unknown payload keys #{unknown.sort.inspect}"
        next
      end
      payload_class.from_hash(deep_stringify_keys(payload))
      validated += 2
      next
    end
    unless Ituob::Models.const_defined?(resolved)
      failures << "#{issue}/#{rel}: cannot resolve class #{resolved.inspect}"
      next
    end
    Ituob::Models.const_get(resolved).from_yaml(data.to_yaml, permitted_classes: [Date, Time])
    validated += 1
  rescue StandardError => e
    failures << "#{issue}/#{rel}: #{e.class}: #{e.message.lines.first.strip}"
  end
end

# Dataset change objects (register patches): every
# datasets/{slug}/changes/*.yaml loads through Ituob::Registers::Change
# — the register-layer patch model mirrored in the ontology as
# RegisterChange/Identifier (per-op conditionals stay in the JSON
# Schema gated by `ituob dataset validate`).
Dir.glob(File.expand_path('../datasets/*/changes/*.yaml', __dir__)).sort.each do |path|
  rel = path.sub(%r{.*/datasets/}, '')
  hash = YAML.load_file(path, permitted_classes: [Date, Time], aliases: true)
  Ituob::Registers::Change.from_hash(hash)
  validated += 1
rescue StandardError => e
  failures << "#{rel}: #{e.class}: #{e.message.lines.first.strip}"
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
