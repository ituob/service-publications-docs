#!/usr/bin/env ruby
# frozen_string_literal: true

# Merges the per-publication render shards of .github/workflows/pdf.yml into
# the one `publications` artifact the site fetches (ituob.github.io#112):
# OUT/manifest.json plus OUT/pdf/<standard>-<year>/*.pdf at the paths the
# manifest names.
#
#   ruby scripts/merge_publication_manifests.rb --parts DIR --out DIR [--expect N]
#
# DIR holds one sub-directory per shard, each as render_publications.rb left it
# (pdf/manifest.json, pdf/**.pdf and render-failures.log). Fail closed: a shard
# without a manifest, a non-empty render-failures.log, a PDF missing or not
# matching its sha256, two entries on one (standard, edition_year, language) or
# one path, or fewer shards than --expect is an error and nothing is written.

require 'json'
require 'digest'
require 'fileutils'
require 'optparse'

module MergePublicationManifests
  class Error < StandardError; end

  module_function

  def merge(parts:, out:, expect: nil)
    shards = Dir.children(parts).sort.map { |n| File.join(parts, n) }.select { |d| File.directory?(d) }
    errors = []
    errors << "expected #{expect} shards, found #{shards.size}" if expect && shards.size != expect
    entries = []
    shards.each { |shard| collect(shard, entries, errors) }
    check_unique(entries, errors)
    raise Error, errors.join("\n") unless errors.empty?

    write(parts, shards, entries, out)
    entries
  end

  def collect(shard, entries, errors)
    name = File.basename(shard)
    log = File.join(shard, 'render-failures.log')
    errors << "#{name}: no render-failures.log" unless File.exist?(log)
    errors << "#{name}: render failures:\n#{File.read(log)}" if File.size?(log)
    manifest = File.join(shard, 'pdf', 'manifest.json')
    return errors << "#{name}: no pdf/manifest.json" unless File.file?(manifest)

    list = JSON.parse(File.read(manifest)).fetch('publications')
    errors << "#{name}: manifest lists no publications" if list.empty?
    list.each do |e|
      file = File.join(shard, e.fetch('path'))
      if !File.size?(file) then errors << "#{name}: #{e['path']} missing or empty"
      elsif Digest::SHA256.file(file).hexdigest != e['sha256'] then errors << "#{name}: #{e['path']} sha256 mismatch"
      else entries << [e, file]
      end
    end
  end

  def check_unique(entries, errors)
    { 'edition' => ->(e) { e.values_at('standard', 'edition_year', 'language') },
      'path' => ->(e) { e['path'] } }.each do |what, key|
      entries.group_by { |e, _| key.call(e) }.each do |k, v|
        errors << "duplicate #{what} #{k.inspect}" if v.size > 1
      end
    end
  end

  def write(parts, shards, entries, out)
    FileUtils.rm_rf(out)
    entries.each do |e, file|
      dest = File.join(out, e['path'])
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(file, dest)
    end
    sorted = entries.map(&:first).sort_by { |e| e.values_at('standard', 'edition_year', 'language') }
    File.write(File.join(out, 'manifest.json'), "#{JSON.pretty_generate('publications' => sorted)}\n")
    raise Error, "#{parts}: #{shards.size} shards but no entries" if sorted.empty?
  end

  def main(argv)
    parts = out = expect = nil
    OptionParser.new do |o|
      o.on('--parts DIR') { |v| parts = v }
      o.on('--out DIR') { |v| out = v }
      o.on('--expect N', Integer) { |v| expect = v }
    end.parse!(argv)
    abort 'usage: --parts DIR --out DIR [--expect N]' unless parts && out
    entries = merge(parts: parts, out: out, expect: expect)
    puts "merged #{entries.size} PDFs from #{Dir.children(parts).size} shards into #{out}"
  rescue Error => e
    warn e.message
    exit 1
  end
end

MergePublicationManifests.main(ARGV) if $PROGRAM_NAME == __FILE__
