#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Regenerate per-change files under each register's changes/ directory
# from the certified per-issue corpus (ob-issues/{N}/{slug}/). One
# change file per printed amendment action, so a multi-row amendment
# stays atomic and the replay can key every row from its entries.
#
#   datasets/{seed_issue}-{slug}/changes/{ob_issue}-{seq}-{ACTION}-{key}.yaml
#
# Single provenance: ob-issues is the certified normalized corpus (the
# legacy actions/amendments trees were an earlier parse of the same
# sources and are no longer read). Idempotent: each run wipes and
# rewrites every register's changes/ directory; git history retains
# the previous generation.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'fileutils'
require 'yaml'

OB_ISSUES_ROOT = File.expand_path('../ob-issues', __dir__)
# seed_path values already include the datasets/ prefix.
PROJECT_ROOT   = File.expand_path('..', __dir__)

REGISTERS_ARG = ARGV[0] # optional: comma-separated list of register_ids

# The source corpus occasionally carries Symbol keys (e.g. F.400's
# :x400). Re-emitting them would produce YAML the strict loaders
# reject; stringify recursively so change files stay plain.
# Canonical register action; the source corpus preserves odd extracted
# codes verbatim (e.g. a country code mistaken for an action), which
# Registers::Change rejects — those publish as ADD.
REGISTER_ACTIONS = %w[ADD SUP REP LIR MOD DEL SEED].freeze

def normalize_action(raw)
  declared_action(raw) || 'ADD'
end

def declared_action(raw)
  cleaned = raw.to_s.upcase.strip
  cleaned if REGISTER_ACTIONS.include?(cleaned)
end

# The file's own `type:` is the printed action. A filename that names
# a different register action is a source-corpus labelling defect: the
# type wins and the disagreement is reported rather than hidden.
def action_for(filename_action, type, path)
  declared = declared_action(type)
  return normalize_action(filename_action) unless declared

  if declared_action(filename_action) && declared != declared_action(filename_action)
    return declared unless WARNED_PATHS.add?(path)

    warn "migrate: #{path} is named #{filename_action} but declares type #{declared}; using #{declared}"
  end
  declared
end

WARNED_PATHS = Set.new

# Amendment rows of one source slug are shared between a register and
# its routed siblings (e.g. the E.164 note lists printed inside the
# E164_CC amendments): a routed register takes the rows it claims, the
# unrouted register the rest.
def rows_owned_by(entry, rows)
  siblings = Ituob::Catalogs::Registers.all.select { |e| e.amendment_slug == entry.amendment_slug }
  rows.select do |row|
    if entry.route
      entry.routes?(row)
    else
      siblings.none? { |sibling| sibling.routes?(row) }
    end
  end
end

# The LML instance format collapses a one-element array of instances
# to the instance itself on parse; normalize the payload to the same
# shape (recursively) so every change file round-trips identically.
def deep_lml_normalize(value)
  case value
  when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_lml_normalize(v) }
  when Array
    normalized = value.map { |v| deep_lml_normalize(v) }
    normalized.length == 1 && normalized[0].is_a?(Hash) ? normalized[0] : normalized
  when Symbol then value.to_s
  else value
  end
end

def deep_stringify(value)
  case value
  when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
  when Array then value.map { |v| deep_stringify(v) }
  when Symbol then value.to_s
  else value
  end
end

def registers_to_migrate
  return Ituob::Catalogs::Registers.all_register_ids unless REGISTERS_ARG

  REGISTERS_ARG.split(',').map(&:strip)
end

stats = Hash.new(0)

registers_to_migrate.each do |register_id|
  entry = Ituob::Catalogs::Registers.find(register_id)
  next unless entry&.seed_path

  target_dir = File.join(PROJECT_ROOT, entry.seed_path, 'changes')
  amendment_dirs = Dir.glob(File.join(OB_ISSUES_ROOT, '*', entry.amendment_slug))
                       .select { |d| File.directory?(d) }

  # Regeneration replaces the previous generation wholesale.
  if Dir.exist?(target_dir)
    Dir.children(target_dir)
       .select { |n| n.end_with?('.yaml', '.yml') }
       .each { |f| File.delete(File.join(target_dir, f)) }
  end
  FileUtils.mkdir_p(target_dir)

  amendment_dirs.sort.each do |dir|
    ob_issue = File.basename(File.dirname(dir)).to_i
    Dir.children(dir)
       .select { |n| n =~ /\A\d+-[A-Z][A-Z0-9]*\.yaml\z/ }
       .sort
       .each do |name|
      seq, raw_action = name.match(/\A(\d+)-([A-Z][A-Z0-9]*)\.yaml\z/).captures
      seq = seq.to_i
      path = File.join(dir, name)
      source = YAML.safe_load(File.read(path), aliases: true,
                              permitted_classes: [Date, Time, DateTime, Symbol])
      next unless source.is_a?(Hash)

      action = action_for(raw_action, source['type'], path.delete_prefix("#{PROJECT_ROOT}/"))
      data = source['data'].is_a?(Hash) ? source['data'] : {}
      printed_entries = data['entries'].is_a?(Array) ? data['entries'] : []
      entries = rows_owned_by(entry, printed_entries)
      next if printed_entries.any? && entries.empty?
      # A list repeat that prints no rows names no key to repeat.
      next if action == 'LIR' && printed_entries.empty?
      next if printed_entries.empty? && entry.route

      key_field = entry.key_field
      fallbacks = Array(entry.fallback_key_fields)
      # First entry key is informational (the replay keys rows itself);
      # the synthetic fallback marks changes whose rows key by other
      # means.
      key = entries.map { |e| Ituob::Registers::Strategies::Base.entry_key(e, key_field, fallbacks) }
                   .compact.first
      key ||= format('%d-%04d', ob_issue, seq)

      # Payload shape: a single-row amendment stores the row directly
      # (flat, like the replay's legacy inputs); multi-row amendments
      # keep the entries array. The LML instance format collapses
      # single-element instance arrays on parse, so a one-row
      # entries array must never be emitted.
      payload_data =
        if entries.length == 1
          entries.first
        elsif entries.empty?
          data.reject { |k, _| k == 'entries' }
        else
          data.merge('entries' => entries)
        end

      payload = {
        'type' => action,
        'register' => register_id,
        'recommendation' => entry.recommendation,
        'ob_issue_no' => ob_issue.to_s,
        'identifier' => { 'code' => key.to_s },
        'data' => deep_stringify(deep_lml_normalize(payload_data)),
        'reference' => source['reference'],
        'date_active' => source['date_active'],
      }.compact

      safe_key = String(key).gsub(/[^a-zA-Z0-9._-]/, '_')[0..60]
      filename = format('%04d-%04d-%s-%s.yaml', ob_issue, seq, action, safe_key)
      File.write(File.join(target_dir, filename), payload.to_yaml.gsub(/\A---\n/, ''))
      stats[:written] += 1
    end
    stats[:issues] += 1
  end
  stats[:registers] += 1
end

puts "Migration: #{stats[:registers]} registers, #{stats[:issues]} amendment issues, " \
     "#{stats[:written]} change files written"
