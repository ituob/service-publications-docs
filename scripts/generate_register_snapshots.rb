#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Run the replay engine for each register and emit JSON snapshots
# for the Astro site to render. One snapshot per (slug, ob_issue)
# that touched the register, plus a "current" snapshot.
#
# Output: ituob.org-v2/data/snapshots/{slug}/current.json
#         ituob.org-v2/data/snapshots/{slug}/at-{N}.json
#
# Thin orchestration: build a Replay per register, hand the resulting
# states to Ituob::Registers::SnapshotWriter.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob/support'
require 'ituob/registers'
require 'ituob/catalogs'
require 'ituob/verifiers'
require 'fileutils'
require 'json'

REGISTERS_ARG = ARGV[0]
OUTPUT_ROOT   = ENV.fetch('SNAPSHOTS_OUT',
                          File.expand_path('../../ituob.org-v2/data/snapshots', __dir__))

def registers_to_snapshot
  return Ituob::Catalogs::Registers.all_register_ids unless REGISTERS_ARG

  REGISTERS_ARG.split(',').map(&:strip)
end

# Build a Replay for one catalog entry. Returns nil for external or
# seed-less registers (skipped cleanly — not an error).
def build_replay(entry)
  return nil if entry.external? || entry.seed_path.nil?

  source = Ituob::Registers::DirectoryChangeSource.new(
    register_id: entry.register_id,
    seed_path: entry.seed_path,
    seed_issue: entry.seed_issue,
    key_field: entry.key_field,
  )
  Ituob::Registers::Replay.new(
    register_id: entry.register_id,
    key_field: entry.key_field,
    source: source,
  )
end

# Returns the count of files written for this register, or :skipped
# if the register has no snapshot data (external / no seed).
def snapshot_register(register_id, writer)
  entry = Ituob::Catalogs::Registers.find(register_id)
  raise "unknown register #{register_id.inspect}" unless entry

  replay = build_replay(entry)
  return :skipped if replay.nil?

  all_states = replay.build_all_states
  writer.write(
    slug: entry.slug,
    manifest_fields: {
      register_id: entry.register_id,
      recommendation: entry.recommendation,
      title: entry.title,
      key_field: entry.key_field,
      seed_issue: entry.seed_issue,
    },
    current_state: all_states[nil],
    states_by_issue: all_states,
  )
end

# === main ===

stats = Hash.new(0)
writer = Ituob::Registers::SnapshotWriter.new(output_root: OUTPUT_ROOT)

registers_to_snapshot.each do |register_id|
  result = snapshot_register(register_id, writer)
  if result == :skipped
    stats[:skipped] += 1
  else
    stats[:snapshots] += result
    stats[:registers] += 1
  end
rescue StandardError => e
  warn "skip #{register_id}: #{e.class}: #{e.message}"
  stats[:errors] += 1
end

puts "Snapshots: #{stats[:registers]} registers, #{stats[:snapshots]} files written, " \
     "#{stats[:skipped]} skipped, #{stats[:errors]} errors"

# Post-generation integrity check: ensure every snapshot's manifest
# matches the catalog. Exit non-zero on failure so CI catches drift.
verifier = Ituob::Verifiers::SnapshotIntegrityVerifier.new(snapshots_root: OUTPUT_ROOT)
integrity = verifier.verify
if integrity.errors.any?
  warn ""
  warn "Snapshot integrity FAILED:"
  integrity.errors.each { |e| warn "  #{e}" }
  exit 1
end
if integrity.warnings.any?
  warn ""
  warn "Snapshot integrity warnings:"
  integrity.warnings.each { |w| warn "  #{w}" }
end
puts "Snapshot integrity: #{integrity.errors.length} errors, #{integrity.warnings.length} warnings"
