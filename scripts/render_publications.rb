#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders service publications to PDF and emits pdf/manifest.json
# (spd#89, tasks 4, 7, 8; design: docs/pdf/manifest.adoc).
#
#   ruby scripts/render_publications.rb [--root DIR] [--out-dir DIR]
#        [--docs T-SP-PP.RES.21-2011,...] [--langs E,F,S] [--strict]
#
# For every selected publication x language it runs
# `metanorma -t itu -x pdf --agree-to-terms`, copies the PDF to its
# deterministic path under OUT_DIR, computes the SHA-256 and writes the
# manifest through Ituob::Models::PublicationManifest. A render that fails, or
# whose row has no numbered dataset (so no as_of_issue), is left out of the
# manifest and written to OUT_DIR/render-failures.log. --strict exits 1 when
# any selected render failed. The manifest carries no wall-clock value.
#
# status is read, never computed: documents/<dir>/publication-status.yaml
# (a `status:` line) when present, else `candidate`.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'liquid'
require 'digest'
require 'fileutils'
require 'open3'
require 'optparse'
require 'ituob'
require_relative 'build_pdf_coverage_matrix'

module RenderPublications
  # Document language letter => [manifest language code, metadata title keys].
  LANGUAGES = {
    'E' => ['en', %w[en]], 'F' => ['fr', %w[fr]], 'S' => ['es', %w[es]],
    'R' => ['ru', %w[ru]], 'C' => ['zh', %w[zh ch]], 'A' => ['ar', %w[ar]]
  }.freeze
  STATUS_FILE = 'publication-status.yaml'
  METADATA_REF = %r{metadata=(?<path>[^,\]\s]+\.ya?ml)}
  Failure = Struct.new(:file, :reason, keyword_init: true)
  Result = Struct.new(:manifest, :failures, keyword_init: true)

  module_function

  # Default renderer: metanorma writes <name>.pdf beside the source. Returns
  # [pdf_path, nil] or [nil, reason].
  def metanorma_renderer(adoc)
    # The manifest gems run under their own bundle; metanorma needs its own.
    run = proc { Open3.capture3('metanorma', '-t', 'itu', '-x', 'pdf', '--agree-to-terms', adoc) }
    _out, err, status = defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
    pdf = adoc.sub(/\.adoc\z/, '.pdf')
    return [nil, "metanorma exit #{status.exitstatus}: #{err.lines.last.to_s.strip}"] unless status.success?
    return [nil, 'metanorma produced no PDF'] unless File.size?(pdf)

    [pdf, nil]
  end

  # renderer: callable(adoc_path) => [pdf_path, nil] | [nil, reason]
  def run(root:, out_dir:, docs: nil, langs: nil, renderer: method(:metanorma_renderer))
    rows = PdfCoverageMatrix.rows(root)
    if docs
      unknown = docs - rows.map { |r| "T-SP-#{r.standard}-#{r.year}" }
      raise ArgumentError, "unknown publication(s): #{unknown.join(', ')}" unless unknown.empty?

      rows = rows.select { |r| docs.include?("T-SP-#{r.standard}-#{r.year}") }
    end
    rows = rows.select { |r| langs.include?(r.language) } if langs
    registers = PdfCoverageMatrix.register_index(root)
    entries = []
    failures = []
    rows.each do |row|
      entry, reason = build_entry(root, out_dir, row, registers, renderer)
      entry ? entries << entry : failures << Failure.new(file: row.file, reason: reason)
    end
    write_manifest(out_dir, entries)
    write_log(out_dir, failures)
    Result.new(manifest: Ituob::Models::PublicationManifest.new(publications: entries), failures: failures)
  end

  def build_entry(root, out_dir, row, registers, renderer)
    return [nil, 'no numbered dataset, so no as_of_issue'] unless row.issue

    dir = File.join(root, 'documents', "T-SP-#{row.standard}-#{row.year}")
    adoc = File.join(dir, row.file)
    code, keys = LANGUAGES.fetch(row.language)
    title = title_for(adoc, keys)
    return [nil, "no title for #{code} in the dataset metadata"] unless title

    pdf, reason = renderer.call(adoc)
    return [nil, reason] unless pdf

    rel = "pdf/#{row.standard}-#{row.year}/#{row.standard}-#{row.year}-#{row.language}.pdf"
    dest = File.join(out_dir, rel)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(pdf, dest)
    [Ituob::Models::PublicationManifestEntry.new(
      standard: row.standard, recommendation: recommendation(row.standard), title: title,
      edition_year: row.year.to_i, language: code, as_of_issue: row.issue,
      sha256: Digest::SHA256.file(dest).hexdigest, status: status_for(dir),
      register_slugs: row.registers.map(&:slug), path: rel
    ), nil]
  rescue Lutaml::Model::Error, ArgumentError, SystemCallError => e
    [nil, "#{e.class}: #{e.message}"]
  end

  # `E.164B` => `E.164`: drop one trailing uppercase letter that follows a digit.
  def recommendation(standard)
    standard.sub(/(?<=\d)[A-Z]\z/, '')
  end

  # metadata.title[<code>] of the first dataset the document reads.
  def title_for(adoc, keys)
    ref = File.read(adoc, encoding: 'UTF-8').lines.grep(PdfCoverageMatrix::BLOCK_LINE)
              .filter_map { |l| METADATA_REF.match(l) }.first
    return unless ref

    meta = Ituob::Support::Yaml.safe_load_file(File.expand_path(ref[:path], File.dirname(adoc)))
    titles = meta.is_a?(Hash) ? meta['title'] : nil
    return unless titles.is_a?(Hash)

    keys.filter_map { |k| titles[k].to_s.strip }.find { |t| !t.empty? }
  rescue SystemCallError
    nil
  end

  def status_for(dir)
    file = File.join(dir, STATUS_FILE)
    return 'candidate' unless File.exist?(file)

    status = Ituob::Support::Yaml.safe_load_file(file)&.fetch('status', nil) || 'candidate'
    unless Ituob::Models::PublicationManifestEntry::STATUSES.include?(status)
      raise ArgumentError, "#{file}: invalid status #{status.inspect}"
    end

    status
  end

  def write_manifest(out_dir, entries)
    FileUtils.mkdir_p(File.join(out_dir, 'pdf'))
    manifest = Ituob::Models::PublicationManifest.new(publications: entries)
    File.write(File.join(out_dir, 'pdf', 'manifest.json'), "#{manifest.to_json(pretty: true)}\n")
  end

  def write_log(out_dir, failures)
    log = File.join(out_dir, 'render-failures.log')
    File.write(log, failures.map { |f| "#{f.file}: #{f.reason}\n" }.join)
  end

  def main(argv)
    root = File.expand_path('..', __dir__)
    out_dir = nil
    docs = langs = nil
    strict = false
    OptionParser.new do |o|
      o.on('--root DIR') { |v| root = File.expand_path(v) }
      o.on('--out-dir DIR') { |v| out_dir = File.expand_path(v) }
      o.on('--docs LIST') { |v| docs = v.split(',') }
      o.on('--langs LIST') { |v| langs = v.split(',') }
      o.on('--strict') { strict = true }
    end.parse!(argv)
    result = run(root: root, out_dir: out_dir || File.join(root, 'build'), docs: docs, langs: langs)
    puts "manifest: #{result.manifest.publications.size} entries, #{result.failures.size} failed"
    result.failures.each { |f| warn "FAILED #{f.file}: #{f.reason}" }
    exit(1) if strict && !result.failures.empty?
  end
end

RenderPublications.main(ARGV) if $PROGRAM_NAME == __FILE__
