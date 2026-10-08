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
    # Freeform positions are skipped before reading: their payloads may
    # contain YAML aliases the strict loader rejects.
    if Ituob::Support::CorpusTree.class_name_for(rel).nil?
      skipped += 1
      next
    end

    data = YAML.load_file(path, permitted_classes: [Date, Time])
    resolved = Ituob::Support::CorpusTree.resolve_for(rel, data)
    if resolved.nil?
      skipped += 1
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

puts "issues checked: #{selected.length}; files validated: #{validated}; skipped (freeform): #{skipped}"
if failures.empty?
  puts 'INSTANCE DATA VALID'
  exit 0
else
  puts "FAILURES: #{failures.length}"
  failures.first(25).each { |f| puts "  #{f}" }
  exit 1
end
