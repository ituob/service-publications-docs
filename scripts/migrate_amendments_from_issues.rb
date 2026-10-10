#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Migrate amendment data from OB issue YAML to schema-change.yaml
# format for registers that currently only have seed data.
#
# For each register without a changes/ directory:
# 1. Find all OB issues that amend it
# 2. Load the amendment ProseMirror doc
# 3. Extract table rows as structured entries
# 4. Write one ADD change per row to datasets/{seed_path}/changes/

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob/support'
require 'ituob/catalogs'
require 'yaml'
require 'fileutils'
require 'json'

OB_ISSUES_ROOT = File.expand_path('../../itu-ob-data/issues', __dir__)
DATASETS_ROOT  = File.expand_path('../datasets', __dir__)

# Extract text from a ProseMirror node tree.
def walk_text(node)
  return '' if node.nil?

  parts = []
  case node
  when Hash
    parts << node['text'] if node['type'] == 'text'
    if node['content'].is_a?(Array)
      node['content'].each { |c| parts << walk_text(c) }
    end
  when Array
    node.each { |c| parts << walk_text(c) }
  end
  parts.reject { |p| !p.is_a?(String) || p.empty? }.join(' ')
end

# Extract table rows from a ProseMirror doc.
# Returns array of arrays: [[cell1, cell2, ...], ...]
def extract_table_rows(doc)
  rows = []
  find_table_rows(doc, rows)
  rows
end

def find_table_rows(node, rows)
  case node
  when Hash
    if node['type'] == 'table_row'
      cells = []
      (node['content'] || []).each do |cell_node|
        next unless cell_node.is_a?(Hash) && cell_node['type'] == 'table_cell'
        cells << walk_text(cell_node).strip
      end
      rows << cells unless cells.empty?
    end
    if node['content'].is_a?(Array)
      node['content'].each { |c| find_table_rows(c, rows) }
    end
  when Array
    node.each { |c| find_table_rows(c, rows) }
  end
end

# Build a changes/ directory for one register from its amendments.
def migrate_register(register_entry)
  register_id = register_entry.register_id
  slug = register_entry.slug
  seed_path = register_entry.seed_path
  key_field = register_entry.key_field
  seed_issue = register_entry.seed_issue

  return nil if register_entry.external?
  return nil unless seed_path

  changes_dir = File.join(seed_path, 'changes')
  return "#{slug}: already has changes/" if Dir.exist?(changes_dir) && !Dir.children(changes_dir).empty?

  FileUtils.mkdir_p(changes_dir)

  # Find all issues that have amendments for this register.
  issue_ids = Dir.children(OB_ISSUES_ROOT)
    .map { |n| n.to_i if n.match?(/\A\d+\z/) }
    .compact.sort

  changes_written = 0
  issue_ids.each do |issue_id|
    next if issue_id <= (seed_issue || 0)

    amendments_path = File.join(OB_ISSUES_ROOT, issue_id.to_s, 'amendments.yaml')
    next unless File.file?(amendments_path)

    data = Ituob::Support::Yaml.safe_load_file(amendments_path)
    messages = (data || {}).fetch('messages', [])

    # Find the amendment for this register.
    amendment = messages.find do |m|
      m['target'] && m['target']['publication'] == register_id
    end
    next unless amendment

    # Extract the ProseMirror doc.
    doc = amendment.dig('contents', 'en')
    next unless doc

    # Extract table rows.
    rows = extract_table_rows(doc)
    next if rows.empty?

    # Find the header row and key column. Two-pass search:
    # 1. Exact key_field match (normalized) — e.g. "country_code" → "countrycode" matches "Country code"
    # 2. Generic fallback patterns — "code", "carrier", "country", etc.
    key_norm = key_field.to_s.downcase.gsub(/[\s_\/-]+/, '')
    generic_patterns = %w[code carrier country mcc sanc ispc iin dnic]
    header_idx = nil
    key_col = nil

    # Pass 1: exact key_field match
    rows.each_with_index do |row, idx|
      row_lower = row.map { |h| h.downcase.gsub(/[\s_\/-]+/, '') }
      found_col = row_lower.find_index { |h| h.include?(key_norm) }
      if found_col
        header_idx = idx
        key_col = found_col
        break
      end
    end

    # Pass 2: generic patterns (only if pass 1 failed)
    unless header_idx
      rows.each_with_index do |row, idx|
        row_lower = row.map { |h| h.downcase.gsub(/[\s_\/-]+/, '') }
        found_col = row_lower.find_index { |h| generic_patterns.any? { |p| h.include?(p) } }
        if found_col
          header_idx = idx
          key_col = found_col
          break
        end
      end
    end

    # Fall back to first row if no header match found.
    header_idx ||= 0
    header = rows[header_idx].map { |h| h.downcase.strip }
    key_col ||= 0

    # Write one ADD change per data row (skip header rows).
    data_rows = rows[(header_idx + 1)..-1] || []
    seq = 0
    data_rows.each do |cells|
      next if cells.empty? || cells.all? { |c| c.nil? || c.strip.empty? }

      # Build entry data from cells.
      entry = {}
      header.each_with_index do |h, i|
        entry[h.strip] = cells[i] if cells[i] && !cells[i].empty?
      end

      # Extract key value.
      key_value = key_col < cells.length ? cells[key_col] : cells.first
      next unless key_value && !key_value.empty?
      key_value = key_value.strip
      next if key_value.length > 100 # skip excessively long values (likely headers/notes)
      next if key_value.match?(/\A\s*\z/) # skip whitespace-only

      seq += 1
      change = {
        'type' => 'ADD',
        'register' => register_id,
        'ob_issue_no' => issue_id.to_s,
        'identifier' => { 'code' => key_value },
        'data' => entry,
      }

      safe_key = key_value.gsub(/[^a-zA-Z0-9]/, '_').slice(0, 40)
      filename = format('%04d-%03d-ADD-%s.yaml', issue_id, seq, safe_key)
      File.write(File.join(changes_dir, filename), change.to_yaml)
      changes_written += 1
    end
  end

  "#{slug}: wrote #{changes_written} change files from #{issue_ids.length} issues"
end

# === main ===

puts "Migrating amendments for registers without changes/..."
results = []
Ituob::Catalogs::Registers.each_entry do |entry|
  result = migrate_register(entry)
  results << result if result
end

results.each { |r| puts "  #{r}" }
puts ""
total = results.sum { |r| r[/wrote (\d+)/, 1]&.to_i || 0 }
puts "Total: #{total} change files written"
