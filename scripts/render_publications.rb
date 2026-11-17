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
# (a `status:` line) when present, else `candidate`. A status file that is not
# a mapping, or whose `status` is not one of the known strings (false, empty,
# a number), fails that entry instead of defaulting.
#
# Fail closed: whatever one entry does (the renderer raises, a status file is
# malformed, the entry breaks a rule the site enforces) only fails that entry.
# The manifest and the log are always written; a manifest or log left by an
# earlier run is deleted first, so an aborted run cannot leave a stale one.
#
# The container runs `metanorma` under its own bundle (RUBYOPT, BUNDLE_GEMFILE).
# This script runs under ituob/Gemfile, so the workflow passes the container's
# original values in RENDER_ORIG_RUBYOPT and RENDER_ORIG_BUNDLE_GEMFILE and the
# metanorma subprocess gets exactly those (empty means unset).

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
  MAX_SAFE_INTEGER = (2**53) - 1
  # The site's entry rules (ituob.github.io src/lib/publications.ts parseEntry).
  SHA256_RE = /\A\h{64}\z/
  SLUG_RE = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  LANG_RE = /\A[a-z]{2,3}(-[A-Za-z0-9]+)?\z/
  UNSAFE_PATH_CHARS = /[\u0000-\u001f\u007f?#%]/
  PATH_SCHEME = /\A[a-z][a-z0-9+.-]*:/i
  METADATA_REF = %r{metadata=(?<path>[^,\]\s]+\.ya?ml)}
  Failure = Struct.new(:file, :reason, keyword_init: true)
  Result = Struct.new(:manifest, :failures, keyword_init: true)

  module_function

  # Env for the metanorma subprocess: the container's original bundler env
  # captured by the workflow (RENDER_ORIG_*), applied over an unbundled env.
  def metanorma_env(environ = ENV)
    %w[RUBYOPT BUNDLE_GEMFILE].each_with_object({}) do |name, env|
      orig = environ["RENDER_ORIG_#{name}"]
      env[name] = orig.to_s.empty? ? nil : orig unless orig.nil?
    end
  end

  # Default renderer: metanorma writes <name>.pdf beside the source. Returns
  # [pdf_path, nil] or [nil, reason]. A PDF left beside the source by an
  # earlier run is deleted first, so only a fresh render can succeed.
  def metanorma_renderer(adoc)
    pdf = adoc.sub(/\.adoc\z/, '.pdf')
    FileUtils.rm_f(pdf)
    env = metanorma_env.merge(provider_env)
    run = proc { Open3.capture3(env, 'metanorma', '-t', 'itu', '-x', 'pdf', '--agree-to-terms', adoc) }
    _out, err, status = defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
    return [nil, "metanorma exit #{status.exitstatus}: #{failure_summary(err)}"] unless status.success?
    return [nil, 'metanorma produced no PDF'] unless File.size?(pdf)

    [pdf, nil]
  end

  # A document may read its register through the ituob data provider
  # (`lutaml_data provider:ituob.edition`); metanorma finds it through
  # ituob/lib/metanorma/plugin/lutaml/data_providers/ituob.rb, so ituob/lib
  # must be on the load path of the metanorma process.
  def provider_env
    lib = File.expand_path('../ituob/lib', __dir__)
    { 'RUBYLIB' => [lib, ENV.fetch('RUBYLIB', nil)].compact.reject(&:empty?).join(File::PATH_SEPARATOR) }
  end

  # The first and last lines say what failed and where; a backtrace line alone does not.
  def failure_summary(err)
    lines = err.lines.map(&:strip).reject(&:empty?)
    (lines.first(3) + ['...'] + lines.last(2)).uniq.join(' | ')
  end

  # renderer: callable(adoc_path) => [pdf_path, nil] | [nil, reason]
  def run(root:, out_dir:, docs: nil, langs: nil, renderer: method(:metanorma_renderer))
    clear_outputs(out_dir)
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
      entry, reason = build_entry_safely(root, out_dir, row, registers, renderer)
      reason ||= duplicate_reason(entry, entries) if entry
      entry && reason.nil? ? entries << entry : failures << Failure.new(file: row.file, reason: reason)
    end
    write_manifest(out_dir, entries)
    write_log(out_dir, failures)
    Result.new(manifest: Ituob::Models::PublicationManifest.new(publications: entries), failures: failures)
  end

  # Output of an earlier run (manifest, log, PDFs) must not outlive a run that
  # aborts or fails an entry, or it would be uploaded as if it were this run's.
  def clear_outputs(out_dir)
    FileUtils.rm_rf(File.join(out_dir, 'pdf'))
    FileUtils.rm_f(File.join(out_dir, 'render-failures.log'))
  end

  # Any StandardError from one row (a raising renderer, a malformed status
  # file, a bad dataset) becomes that row's failure; the run goes on.
  def build_entry_safely(root, out_dir, row, registers, renderer)
    entry, reason = build_entry(root, out_dir, row, registers, renderer)
    return [nil, reason || 'entry could not be built'] unless entry

    reason = invalid_reason(entry)
    reason ? [nil, reason] : [entry, nil]
  rescue StandardError => e
    [nil, "#{e.class}: #{e.message}"]
  end

  def duplicate_reason(entry, entries)
    if entries.any? { |e| [e.standard, e.edition_year, e.language] == [entry.standard, entry.edition_year, entry.language] }
      return "duplicate edition #{entry.edition_year} for #{entry.standard}/#{entry.language}"
    end

    "duplicate path #{entry.path}" if entries.any? { |e| e.path == entry.path }
  end

  # The rules the site applies to an entry (parseEntry); a violation here
  # would only be dropped by the site, so it is a failed render instead.
  def invalid_reason(entry)
    return 'blank standard' if entry.standard.to_s.strip.empty?
    return 'blank title' if entry.title.to_s.strip.empty?
    return "invalid edition_year #{entry.edition_year.inspect}" unless positive_safe_int?(entry.edition_year)
    return "invalid language #{entry.language.inspect}" unless LANG_RE.match?(entry.language.to_s)
    return "invalid as_of_issue #{entry.as_of_issue.inspect}" unless positive_safe_int?(entry.as_of_issue)
    return 'invalid sha256' unless SHA256_RE.match?(entry.sha256.to_s)
    return "invalid status #{entry.status.inspect}" unless Ituob::Models::PublicationManifestEntry::STATUSES.include?(entry.status)
    return "unsafe path #{entry.path.inspect} (must be a relative .pdf)" unless safe_pdf_path?(entry.path.to_s)

    bad = entry.register_slugs.reject { |slug| SLUG_RE.match?(slug.to_s) }
    "invalid register_slugs #{bad.inspect}" unless bad.empty?
  end

  def positive_safe_int?(value)
    value.is_a?(Integer) && value.positive? && value <= MAX_SAFE_INTEGER
  end

  def safe_pdf_path?(path)
    return false if path.empty? || UNSAFE_PATH_CHARS.match?(path) || path.start_with?('/') ||
                    path.include?('\\') || PATH_SCHEME.match?(path)

    path.split('/', -1).none? { |seg| ['', '.', '..'].include?(seg) } && path.match?(/\.pdf\z/i)
  end

  def build_entry(root, out_dir, row, registers, renderer)
    return [nil, 'no numbered dataset, so no as_of_issue'] unless row.issue

    dir = File.join(root, 'documents', "T-SP-#{row.standard}-#{row.year}")
    adoc = File.join(dir, row.file)
    code, keys = LANGUAGES.fetch(row.language)
    title = title_for(adoc, keys, row.datasets.first&.first)
    return [nil, "no title for #{code} in the dataset metadata"] unless title

    pdf, reason = renderer.call(adoc)
    return [nil, reason || 'renderer returned no PDF and no reason'] unless pdf
    return [nil, "renderer returned an empty or missing PDF: #{pdf}"] unless File.size?(pdf)

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
  end

  # `E.164B` => `E.164`: drop one trailing uppercase letter that follows a digit.
  def recommendation(standard)
    standard.sub(/(?<=\d)[A-Z]\z/, '')
  end

  # metadata.title[<code>] of the first dataset the document reads: the one its
  # first yaml2text block names, else (a provider block names none) the
  # metadata of its first dataset directory.
  def title_for(adoc, keys, dataset = nil)
    ref = File.read(adoc, encoding: 'UTF-8').lines.grep(PdfCoverageMatrix::BLOCK_LINE)
              .filter_map { |l| METADATA_REF.match(l) }.first
    path = ref ? File.expand_path(ref[:path], File.dirname(adoc)) : dataset_metadata(adoc, dataset)
    return unless path

    meta = Ituob::Support::Yaml.safe_load_file(path)

    titles = meta.is_a?(Hash) ? meta['title'] : nil
    return unless titles.is_a?(Hash)

    keys.filter_map { |k| titles[k].to_s.strip }.find { |t| !t.empty? }
  rescue SystemCallError
    nil
  end

  def dataset_metadata(adoc, dataset)
    return unless dataset

    path = File.expand_path("../../datasets/#{dataset}/metadata.yaml", File.dirname(adoc))
    path if File.file?(path)
  end

  def status_for(dir)
    file = File.join(dir, STATUS_FILE)
    return 'candidate' unless File.exist?(file)

    doc = Ituob::Support::Yaml.safe_load_file(file)
    raise ArgumentError, "#{file}: expected a mapping, got #{doc.class}" unless doc.is_a?(Hash)

    status = doc.fetch('status', 'candidate')
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
