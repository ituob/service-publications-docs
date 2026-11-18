#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Instance-data gate: loads every ob-issues YAML file through the
# compiled-from-LML classes, so the corpus is provably valid against
# the ontology-defined shapes.
#
#   BUNDLE_GEMFILE=ituob/Gemfile bundle exec ruby scripts/validate_data_lml.rb [--all | --annexes-only | --datasets-only]
#
# Default validates a deterministic sample (first + last issue of each
# decade); --all walks the full corpus. Exits 1 on any failure.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'yaml'

# Dataset seeds use the same ontology mapping as schema generation. Keep this
# mode independent of the issue corpus so CI checks every seed on every change.
if ARGV.include?('--datasets-only')
  datasets_root = File.expand_path(ENV.fetch('ITUOB_DATASETS_ROOT', '../datasets'), __dir__)
  mapping = YAML.load_file(File.expand_path('../ituob/lib/ituob/ontology/data_schemas.yaml', __dir__))
  paths = Dir.glob(File.join(datasets_root, '*', 'data.yaml')).sort
  failures = []
  validated = 0
  failures << "#{datasets_root}: no dataset data.yaml files found" if paths.empty?
  paths.each do |path|
    slug = File.basename(File.dirname(path))
    class_name = mapping.fetch(slug) { raise ArgumentError, 'no ontology Entry mapping' }
    model_class = Ituob::Models.const_get(class_name, false)
    rows = YAML.load_file(path, permitted_classes: [Date, Time], aliases: true)
    raise ArgumentError, 'expected an array of entries' unless rows.is_a?(Array)

    schema_valid, schema_error = Ituob::Dataset.new(File.dirname(path)).validate_data
    raise ArgumentError, schema_error unless schema_valid

    rows.each_with_index do |row, index|
      raise ArgumentError, "row #{index}: expected an entry mapping" unless row.is_a?(Hash)

      model = model_class.from_hash(row)
      errors = model.validate
      unless errors.empty?
        raise ArgumentError, "row #{index}: #{errors.map(&:message).join(', ')}"
      end
      validated += 1
    end
  rescue StandardError => e
    failures << "#{slug}/data.yaml: #{e.class}: #{e.message.lines.first.strip}"
  end
  puts "dataset files checked: #{paths.length}; entries validated: #{validated}"
  if failures.empty?
    puts 'DATASET INSTANCE DATA VALID'
    exit 0
  end

  warn "FAILURES: #{failures.length}"
  failures.each { |failure| warn "  #{failure}" }
  exit 1
end

ALL = ARGV.include?('--all')
ANNEXES_ONLY = ARGV.include?('--annexes-only')
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
selected = if ALL || ANNEXES_ONLY
             issues
           else
             issues.select { |i| (i % 10).zero? || i == issues.min || i == issues.max }
           end
selected -= [669, 1075] if selected.include?(669) && !ALL && !ANNEXES_ONLY # incomplete editions validated separately

failures = []
validated = 0
skipped = 0

# Check the complete inventory even when validating a sample of issues.
freeform_messages = if ANNEXES_ONLY
                      []
                    else
                      YAML.load_file(File.expand_path('../catalogs/freeform_messages.yaml', __dir__)) || []
                    end
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
  paths = if ANNEXES_ONLY
            [File.join(dir, 'annexes.yaml')].select { |path| File.file?(path) }
          else
            Dir.glob(File.join(dir, '**', '*.yaml')).sort
          end
  paths.each do |path|
    rel = path.delete_prefix("#{dir}/")
    # Freeform positions are skipped before reading: their payloads may
    # contain YAML aliases the strict loader rejects.
    if Ituob::Support::CorpusTree.class_name_for(rel).nil?
      skipped += 1
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
    source_yaml = resolved == 'IssueAnnexes' ? File.read(path) : data.to_yaml
    Ituob::Models.const_get(resolved).from_yaml(source_yaml, permitted_classes: [Date, Time])
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
dataset_changes = ANNEXES_ONLY ? [] : Dir.glob(File.expand_path('../datasets/*/changes/*.yaml', __dir__)).sort
dataset_changes.each do |path|
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
