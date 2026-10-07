#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Migrate legacy per-issue amendment data into per-change files under
# each register's changes/ directory. One shot — idempotent.
#
# Sources read in priority order (later wins):
#   1. actions/amendments/{register_id}/{N}.yaml       (legacy parser output)
#   2. ob-issues/{N}/{slug}/{NNN}-{ACTION}.yaml        (current per-issue output)
#
# Output:
#   datasets/{seed_issue}-{slug}/changes/{ob_issue}-{seq}-{ACTION}-{key}.yaml

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'fileutils'
require 'yaml'

ACTIONS_ROOT   = File.expand_path('../actions/amendments', __dir__)
OB_ISSUES_ROOT = File.expand_path('../ob-issues', __dir__)
DATASETS_ROOT  = File.expand_path('../datasets', __dir__)

REGISTERS_ARG = ARGV[0] # optional: comma-separated list of register_ids to migrate

def registers_to_migrate
  return Ituob::Catalogs::Registers.all_register_ids unless REGISTERS_ARG

  REGISTERS_ARG.split(',').map(&:strip)
end

def slug_for_register(register_id)
  Ituob::Catalogs::Registers.slug_for(register_id)
end

def key_field_for(register_id)
  entry = Ituob::Catalogs::Registers.find(register_id)
  entry&.key_field || 'code'
end

def seed_issue_for(register_id)
  Ituob::Catalogs::Registers.find(register_id)&.seed_issue
end

def seed_path_for(register_id)
  Ituob::Catalogs::Registers.find(register_id)&.seed_path
end

# Convert a legacy parser-output file (actions/amendments/{id}/{N}.yaml)
# into an array of change-hash candidates.
def changes_from_legacy_actions_file(path, register_id, ob_issue)
  data = YAML.safe_load(File.read(path), aliases: true,
                                         permitted_classes: [Date, Time, DateTime, Symbol])
  return [] unless data.is_a?(Hash) && data['actions'].is_a?(Array)

  data['actions'].flat_map.each_with_index do |action, action_idx|
    action_type = action['action_type'] || 'ADD'
    entries = action['entries'] || []
    entries.map.with_index do |entry, entry_idx|
      build_change_hash(
        register_id: register_id,
        ob_issue: ob_issue,
        action_type: action_type,
        entry: entry,
        seq: (action_idx + 1) * 100 + entry_idx,
        position: action['position'],
      )
    end
  end
end

# Convert a per-issue ob-issues file into change-hash candidates.
def changes_from_ob_issue_file(path, register_id)
  stem = File.basename(path, '.yaml')
  md = stem.match(/\A(\d+)-([A-Z]+)\z/)
  return [] unless md

  seq = md[1].to_i
  action_type = md[2]
  data = YAML.safe_load(File.read(path), aliases: true,
                                         permitted_classes: [Date, Time, DateTime, Symbol])
  return [] unless data.is_a?(Hash)

  ob_issue = data['ob_issue_no']&.to_i
  date_active = data['date_active']
  reference = data['reference']

  entries = data.dig('data', 'entries') || []
  entries.map.with_index do |entry, idx|
    hash = build_change_hash(
      register_id: register_id,
      ob_issue: ob_issue,
      action_type: action_type,
      entry: entry,
      seq: seq * 100 + idx,
      position: data.dig('data', 'position'),
    )
    hash[:date_active] = date_active if date_active
    hash[:reference] = reference if reference
    hash
  end
end

def build_change_hash(register_id:, ob_issue:, action_type:, entry:, seq:,
                      position: nil)
  key_field = key_field_for(register_id)
  key = extract_key(entry, key_field, position)

  {
    register_id: register_id,
    ob_issue: ob_issue,
    action_type: normalize_action(action_type),
    key: key,
    seq: seq,
    data: entry,
    recommendation: Ituob::Catalogs::Registers.find(register_id)&.recommendation,
  }
end

def extract_key(entry, key_field, position)
  return position if position && entry.nil?
  return entry[key_field] if entry.is_a?(Hash) && entry[key_field]
  return entry[key_field.to_sym] if entry.is_a?(Hash) && entry[key_field.to_sym]

  position || "anon-#{SecureRandom.hex(4)}"
end

def normalize_action(raw)
  cleaned = raw.to_s.upcase.sub(/\*+\z/, '').strip
  # Map legacy/parser-extracted codes to canonical action types.
  case cleaned
  when 'R' then 'REP'
  when 'A' then 'ADD'
  when 'S' then 'SUP'
  when 'L' then 'LIR'
  when 'M' then 'MOD'
  when 'D' then 'DEL'
  when 'P' then 'ADD'      # "P N" position markers
  when /\A\d+\z/ then 'ADD' # numeric values extracted as action_type → ADD
  when /\AADD|SUP|REP|LIR|MOD|DEL|SEED\z/ then cleaned
  else 'ADD'                # default for unrecognised
  end
end

def write_change_file(target_dir, change)
  FileUtils.mkdir_p(target_dir)
  key = String(change[:key] || 'nokey').gsub(/[^a-zA-Z0-9._-]/, '_')[0..60]
  filename = format('%04d-%04d-%s-%s.yaml',
                    change[:ob_issue] || 0, change[:seq], change[:action_type], key)
  path = File.join(target_dir, filename)

  payload = {
    'type' => change[:action_type],
    'register' => change[:register_id],
    'recommendation' => change[:recommendation],
    'ob_issue_no' => change[:ob_issue]&.to_s,
    'identifier' => { 'code' => change[:key].to_s },
    'data' => change[:data] || {},
  }
  payload['reference'] = change[:reference] if change[:reference]
  payload['date_active'] = change[:date_active] if change[:date_active]
  payload.delete_if { |_, v| v.nil? }

  File.write(path, payload.to_yaml.gsub(/\A---\n/, ''))
end

# === main ===

require 'securerandom'

stats = Hash.new(0)
registers_to_migrate.each do |register_id|
  slug = slug_for_register(register_id)
  seed_issue = seed_issue_for(register_id)
  seed_path_rel = seed_path_for(register_id)
  next unless seed_path_rel

  target_dir = File.join(DATASETS_ROOT, '..', seed_path_rel, 'changes')

  # === source 1: legacy actions/amendments/{id}/{N}.yaml ===
  legacy_dir = File.join(ACTIONS_ROOT, register_id)
  if Dir.exist?(legacy_dir)
    Dir.children(legacy_dir)
       .select { |n| n =~ /\A(\d+)(?:-\d+)?\.yaml\z/ }
       .sort
       .each do |name|
      m = name.match(/\A(\d+)/)
      ob_issue = m[1].to_i
      path = File.join(legacy_dir, name)
      changes = changes_from_legacy_actions_file(path, register_id, ob_issue)
      changes.each do |change|
        write_change_file(target_dir, change)
        stats[:written] += 1
      end
    end
  end

  stats[:registers] += 1
end

puts "Migration: #{stats[:registers]} registers, #{stats[:written]} change files written"
