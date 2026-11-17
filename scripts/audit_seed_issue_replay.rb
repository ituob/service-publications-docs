#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only G7 proof. Optional argument: #115's JSONL allowlist, extracted
# with git show <reviewed-head>:scripts/register_state_integrity_allowlist.jsonl.
$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'ituob/registers'
require 'ituob/catalogs'
require 'json'
require 'csv'

root = File.expand_path('..', __dir__)
allowlist = ARGV.empty? ? [] : File.foreach(ARGV.fetch(0)).map { |line| JSON.parse(line) }
duplicates = allowlist.select { |row| row[3] == 'duplicate-add' }
counts = Hash.new(0)
puts CSV.generate_line(%w[register seed_issue patches_before rows_before add_lir_present sup_absent replayed_after g7_duplicate_add_before g7_duplicate_add_after])
Ituob::Catalogs::Registers.all.each do |entry|
  next if entry.external? || entry.seed_path.nil?

  options = {
    register_id: entry.register_id, seed_path: File.expand_path(entry.seed_path, root),
    seed_issue: entry.seed_issue, key_field: entry.key_field
  }
  before = Ituob::Registers::DirectoryChangeSource.for_register(**options).each_sorted.to_a
  seed = before.find(&:seed?)
  patches = before.reject(&:seed?).select { |change| change.ob_issue_no == entry.seed_issue }
  keys = Array(seed&.data).map do |row|
    Ituob::Registers::Strategies::Base.entry_key(row, entry.key_field, entry.fallback_key_fields).to_s
  end
  rows = patches.flat_map do |change|
    Ituob::Registers::Strategies::Base.rows_for(change, entry.key_field, entry.fallback_key_fields).map do |row|
      key = Ituob::Registers::Strategies::Base.entry_key(row, entry.key_field, entry.fallback_key_fields).to_s
      [change.type, keys.include?(key)]
    end
  end
  after = Ituob::Registers::DirectoryChangeSource.for_register(
    **options, seed_includes_seed_issue: entry.seed_includes_seed_issue
  ).each_sorted.reject(&:seed?).select { |change| change.ob_issue_no == entry.seed_issue }
  duplicate_count = duplicates.count { |row| row[0] == entry.register_id && row[1] == entry.seed_issue }
  remaining = after.empty? ? 0 : duplicate_count
  counts[:patches_before] += patches.length
  counts[:rows_before] += rows.length
  counts[:replayed_after] += after.length
  counts[:g7_duplicate_add_before] += duplicate_count
  counts[:g7_duplicate_add_after] += remaining
  puts CSV.generate_line([
    entry.register_id, entry.seed_issue, patches.length, rows.length,
    rows.count { |type, present| %w[ADD LIR].include?(type) && present },
    rows.count { |type, present| type == 'SUP' && !present },
    after.length, duplicate_count, remaining
  ])
end
warn "Totals: #{counts}; allowlist duplicate-add findings: #{duplicates.length}"
exit(counts[:replayed_after].zero? && counts[:g7_duplicate_add_after].zero? ? 0 : 1)
