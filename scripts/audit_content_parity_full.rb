#!/usr/bin/env ruby
# frozen_string_literal: true
# Drives Ituob::Auditors::ContentParity across every deployed issue page
# and produces a per-issue report showing exactly what content is missing
# in the new Astro build.
#
# ROLE: per-ISSUE detail reports (ob-{id}.yaml with section breakdown).
# The parity GATE is scripts/parity_report.rb; use this when you need
# the per-section missing-token detail for one issue.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'fileutils'
require 'yaml'

DEPLOYED_ROOT = ENV.fetch('DEPLOYED_SITE',
                          File.expand_path('../../ituob.org/_site', __dir__))
LOCAL_ROOT = ENV.fetch('LOCAL_DIST',
                       File.expand_path('../../ituob.org-v2/dist', __dir__))

OUTPUT_DIR = ENV.fetch('OUTPUT_DIR',
                       File.expand_path('../scripts/output/parity', __dir__))

SAMPLES = (
  if ARGV.any?
    ARGV.flat_map { |a| a.include?('-') ? Range.new(*a.split('-').map(&:to_i)).to_a : [a.to_i] }
  else
    nil
  end
)

auditor = Ituob::Auditors::ContentParity.new

deployed_issues = Dir.children(File.join(DEPLOYED_ROOT, 'issues'))
                     .select { |n| n =~ /\A\d+-en\z/ }
                     .map { |n| n.sub(/-en\z/, '').to_i }
                     .sort

target_ids = SAMPLES || deployed_issues

FileUtils.mkdir_p(OUTPUT_DIR)

per_issue = []
target_ids.each do |id|
  deployed_path = File.join(DEPLOYED_ROOT, 'issues', "#{id}-en", 'index.html')
  local_path = File.join(LOCAL_ROOT, 'issues', id.to_s, 'index.html')

  unless File.file?(deployed_path) && File.file?(local_path)
    warn "skip OB #{id}: missing #{deployed_path.exist? ? 'local' : 'deployed'}"
    next
  end

  deployed_html = File.read(deployed_path, encoding: 'utf-8')
  local_html = File.read(local_path, encoding: 'utf-8')

  report = auditor.compare(deployed_html, local_html)
  per_issue << { id: id, coverage: report.coverage.round(4), sections: report.sections.length,
                 missing_headings: report.missing_headings.length,
                 missing_links: report.missing_links.length,
                 missing_tables: report.missing_tables.length }

  # Per-issue detail file
  File.write(
    File.join(OUTPUT_DIR, "ob-#{id}.yaml"),
    {
      id: id,
      deployed_tokens: report.deployed_tokens,
      actual_tokens: report.actual_tokens,
      coverage: report.coverage.round(4),
      missing_headings: report.missing_headings,
      missing_links: report.missing_links.first(50),
      missing_tables: report.missing_tables,
      sections: report.sections.map(&:to_section_hash),
    }.to_yaml,
  )
end

# Summary
summary_path = File.join(OUTPUT_DIR, 'summary.yaml')
File.write(summary_path, per_issue.to_yaml)

avg = per_issue.sum { |r| r[:coverage] } / [per_issue.length, 1].max
puts "Audited #{per_issue.length} issues. Avg coverage: #{format('%.1f%%', avg * 100)}"
puts "Per-issue reports in #{OUTPUT_DIR}/ob-{id}.yaml"
puts "Summary: #{summary_path}"

# Print worst 10 issues
worst = per_issue.sort_by { |r| r[:coverage] }.first(10)
puts "Worst 10:"
worst.each do |r|
  puts "  OB #{r[:id]}: #{format('%.1f%%', r[:coverage] * 100)} (#{r[:missing_headings]} headings, #{r[:missing_links]} links, #{r[:missing_tables]} tables)"
end
