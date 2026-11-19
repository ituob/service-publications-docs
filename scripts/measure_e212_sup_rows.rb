#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only. For every E.212 SUP row, compare the printed network with the
# row stored at that point of the replay: same (verbatim reprint, a
# withdrawal), different, or absent. Evidence for G3 in
# docs/normalization/register-close-findings.adoc.
#   BUNDLE_GEMFILE=ituob/Gemfile bundle exec ruby scripts/measure_e212_sup_rows.rb
$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'ituob/registers'
require 'ituob/catalogs'

root = File.expand_path('..', __dir__)
entry = Ituob::Catalogs::Registers.all.find { |e| e.register_id == 'E212_MNC' }
source = Ituob::Registers::DirectoryChangeSource.for_register(
  register_id: 'E212_MNC', seed_path: File.expand_path(entry.seed_path, root),
  seed_issue: entry.seed_issue, seed_includes_seed_issue: entry.seed_includes_seed_issue,
  key_field: entry.key_field
)
builder = Ituob::Registers::StateBuilder.new('E212_MNC')
counts = Hash.new(0)
different = []
source.each_sorted do |change|
  if change.type.to_s == 'SUP' && change.data.is_a?(Hash)
    Array(change.data['entries']).each do |row|
      key = row['mcc_mnc_codes']
      stored = builder.entries[key]
      kind = if stored.nil? then :absent
             elsif stored['networks'].to_s.strip.casecmp?(row['networks'].to_s.strip) then :same
             else :different
             end
      counts[kind] += 1
      different << [change.ob_issue_no, key, stored&.fetch('networks', nil), row['networks']] if kind == :different
    end
  end
  begin
    builder.record_history(change)
    Ituob::Registers::Strategies::Resolver.apply(builder, change, entry.key_field, []) { |_e| nil }
  rescue StandardError
    next
  end
end
p counts
different.each { |row| p row }
