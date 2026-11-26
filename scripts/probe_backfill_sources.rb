#!/usr/bin/env ruby
# frozen_string_literal: true

# Probes ITU for publication-page / dms_pub evidence per backfill number (spd#149).
#
#   ruby scripts/probe_backfill_sources.rb [--root DIR] [--delay SECONDS] [--only N,N..] [--limit N]
#
# Reads docs/backfill/inventory.yaml, appends url/status/content-type/checked_at rows to each
# entry's evidence and writes it back; answers are cached in docs/backfill/probe_cache.json so
# reruns skip them. Run it AFTER build_backfill_inventory.rb (which rewrites the file).
# A 200 for an English MSW/PDF file moves unresolved -> b; everything else is recorded only.

require 'optparse'
require 'yaml'
require_relative 'backfill/source_probe'

module ProbeBackfillSources
  INVENTORY = 'docs/backfill/inventory.yaml'
  CACHE = 'docs/backfill/probe_cache.json'

  module_function

  def run(root:, client:, only: nil, limit: nil, **opts)
    path = File.join(root, INVENTORY)
    doc = YAML.safe_load_file(path)
    targets = doc['inventory'].select { |e| only.nil? || only.include?(e['number']) }
    targets = targets.first(limit) if limit
    probe = Backfill::SourceProbe.new(client: client, cache_path: File.join(root, CACHE), **opts)
    probe.probe_all(targets)
    header = File.read(path)[/\A(?:#.*\n)*/]
    File.write(path, header + doc.to_yaml)
    probe
  end

  def main(argv)
    root = File.expand_path('..', __dir__)
    opts = { delay: 1.0 }
    OptionParser.new do |o|
      o.on('--root DIR') { |v| root = File.expand_path(v) }
      o.on('--delay SECONDS', Float) { |v| opts[:delay] = v }
      o.on('--only LIST') { |v| opts[:only] = v.split(',').map(&:to_i) }
      o.on('--limit N', Integer) { |v| opts[:limit] = v }
    end.parse!(argv)
    run(root: root, client: Backfill::SourceProbe::HttpClient.new, **opts)
  end
end

ProbeBackfillSources.main(ARGV) if $PROGRAM_NAME == __FILE__
