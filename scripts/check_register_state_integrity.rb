#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: check_register_state_integrity.rb [--generate-allowlist | --snapshots-root PATH]
#
# Replays every register and fails on a bad row key or on any replay finding
# (skipped or failed change, lenient replay behaviour, unreadable or
# out-of-range change file, repeated YAML key) that is not in
# scripts/register_state_integrity_allowlist.jsonl. --generate-allowlist
# rewrites that file from the current tree; run it only on main and review
# the diff.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'json'

ALLOWLIST_PATH = File.expand_path('register_state_integrity_allowlist.jsonl', __dir__)
verifier_class = Ituob::Verifiers::RegisterStateIntegrityVerifier

unless ARGV.empty? || ARGV == ['--generate-allowlist'] ||
       (ARGV.length == 2 && ARGV.first == '--snapshots-root')
  abort 'Usage: check_register_state_integrity.rb [--generate-allowlist | --snapshots-root PATH]'
end

if ARGV.first == '--generate-allowlist'
  findings = []
  Ituob::Catalogs::Registers.each_entry do |entry|
    replay = verifier_class.build_replay(entry)
    next unless replay

    findings.concat(verifier_class.replay_findings(replay, replay.current))
  end
  # One JSON array per line: [register, ob_issue, file, kind, detail].
  lines = findings.map { |finding| JSON.generate(verifier_class::FINDING_FIELDS.map { |field| finding[field] }) }
  File.write(ALLOWLIST_PATH, lines.join("\n") + "\n")
  puts "#{lines.length} findings written to #{ALLOWLIST_PATH}"
  exit 0
end

abort "#{ALLOWLIST_PATH} is missing" unless File.file?(ALLOWLIST_PATH)
allowlist = File.readlines(ALLOWLIST_PATH, chomp: true).reject(&:empty?).map do |line|
  verifier_class::FINDING_FIELDS.zip(JSON.parse(line)).to_h
end
snapshots_root = ARGV.first == '--snapshots-root' ? ARGV.last : nil
result = verifier_class.new(allowlist: allowlist, snapshots_root: snapshots_root).verify
result.details.group_by { |detail| detail[:register_id] }.each do |register_id, states|
  current = states.find { |detail| detail[:ob_issue] == 'current' }
  historical = states.reject { |detail| detail[:ob_issue] == 'current' }
  historical_count = historical.sum { |detail| detail[:invalid_entry_count] }
  puts "#{register_id}: current #{current[:invalid_entry_count]}/#{current[:entry_count]} invalid entries; " \
       "historical #{historical_count} invalid entries across #{historical.length} editions"
end
result.warnings.each { |warning| warn "warning: #{warning}" }
result.errors.each { |error| warn error }
puts "#{result.stats[:registers_checked]} registers checked; #{result.stats[:replay_findings]} replay findings, " \
     "#{result.stats[:replay_findings_allowed]} allowlisted; #{result.errors.length} errors"
exit(result.passed? ? 0 : 1)
