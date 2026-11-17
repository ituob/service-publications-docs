#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "optparse"
require_relative "pdf_fidelity_report"

# CI gate: source inventory owns coverage; a reviewed baseline owns fidelity.
module OfficialPdfGate
  class ConfigError < StandardError; end

  KEY = /\A.+-\d{4}-[ACEFRS]\z/
  WORD_RATIOS = %w[recall precision order].freeze
  RATIOS = (WORD_RATIOS + %w[rows cells]).freeze
  PAGES = %w[pages_official pages_generated page_drift].freeze
  EPSILON = 1e-9

  module_function

  def read_mapping(path)
    value = JSON.parse(File.read(path))
    raise ConfigError, "#{path}: expected an object" unless value.is_a?(Hash)

    value.each_key do |key|
      raise ConfigError, "#{path}: invalid publication key #{key.inspect}" unless KEY.match?(key)
    end
    value
  rescue JSON::ParserError, SystemCallError => e
    raise ConfigError, e.message
  end

  def baseline(path)
    read_mapping(path).tap do |entries|
      entries.each do |key, entry|
        valid = entry.is_a?(Hash) && entry["official_sha256"].is_a?(String) &&
          entry["official_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
          valid_ratios?(entry) &&
          PAGES.all? { |metric| entry[metric].is_a?(Integer) && entry[metric] >= 0 }
        valid &&= entry["pages_official"] > 0 && entry["pages_generated"] > 0 &&
          entry["page_drift"] == (entry["pages_generated"] - entry["pages_official"]).abs
        raise ConfigError, "invalid baseline entry #{key}" unless valid
      end
    end
  end

  def ratio?(value)
    value.nil? || (value.is_a?(Numeric) && value.finite? && value.between?(0, 1))
  end

  def valid_ratios?(metrics)
    RATIOS.all? { |metric| metrics.key?(metric) && ratio?(metrics[metric]) } &&
      WORD_RATIOS.all? { |metric| !metrics[metric].nil? && metrics[metric] > 0 }
  end

  def official_files(root)
    index = File.join(root, "docs/pdf/official-pdfs.json")
    files = File.file?(index) ? read_mapping(index) : {}
    files = files.to_h do |key, path|
      raise ConfigError, "invalid official path for #{key}" unless path.is_a?(String) && !path.empty?

      [key, File.expand_path(path, root)]
    end
    Dir[File.join(root, "docs/pdf/official/T-SP-*.pdf")].each do |path|
      key = File.basename(path, ".pdf").delete_prefix("T-SP-")
      raise ConfigError, "invalid official filename #{path}" unless KEY.match?(key)
      raise ConfigError, "duplicate official mapping for #{key}" if files.key?(key)

      files[key] = path
    end
    files
  end

  def inventory(root, docs)
    directories = Dir[File.join(root, "documents/T-SP-*")].select { |path| File.directory?(path) }
    if docs
      unknown = docs - directories.map { |path| File.basename(path) }
      raise ConfigError, "unknown publication directories: #{unknown.join(', ')}" unless unknown.empty?

      directories.select! { |path| docs.include?(File.basename(path)) }
    end
    directories.sort.flat_map do |directory|
      publication = File.basename(directory).delete_prefix("T-SP-")
      Dir[File.join(directory, "*-[ACEFRS].adoc")].map do |source|
        { "key" => "#{publication}-#{File.basename(source, '.adoc')[-1]}", "source" => source }
      end
    end.tap do |rows|
      raise ConfigError, "no publication sources selected" if rows.empty?
      keys = rows.map { |row| row.fetch("key") }
      raise ConfigError, "duplicate source language in publication" unless keys.uniq.size == keys.size
    end
  end

  def differences(current, previous)
    return ["no reviewed baseline"] unless previous

    changes = []
    if current["official_sha256"] != previous["official_sha256"]
      changes << "official SHA256 changed: #{previous['official_sha256']} -> #{current['official_sha256']}"
    end
    RATIOS.each do |metric|
      old = previous[metric]
      value = current[metric]
      if !old.nil? && (value.nil? || old - value > EPSILON)
        changes << "#{metric} declined: #{old} -> #{value.nil? ? 'n/a' : value}"
      end
    end
    if current["page_drift"] > previous["page_drift"]
      changes << "page_drift increased: #{previous['page_drift']} -> #{current['page_drift']}"
    end
    changes
  end

  def compare_row(row, generated, official, previous)
    key = row.fetch("key")
    publication = key[0...-2]
    paths = Dir[File.join(generated, "**", publication, "#{key}.pdf")].select { |path| File.file?(path) }
    errors = []
    errors << "missing generated PDF" if paths.empty?
    errors << "duplicate generated PDFs: #{paths.join(', ')}" if paths.size > 1
    if official.nil?
      errors << "official PDF removed from index/discovery (baseline exists)" if previous
      return row.merge("status" => errors.empty? ? "no official PDF" : "error", "errors" => errors,
                       "official_status" => "no official PDF")
    end
    errors << "missing official PDF: #{official}" unless File.file?(official)
    return row.merge("status" => "error", "errors" => errors) unless errors.empty?

    result = PdfFidelity.compare(paths.first, official)
    raise "official PDF has no extractable words" if result.words_official.zero?
    raise "generated PDF has no extractable words" if result.words_generated.zero?

    metrics = (RATIOS + PAGES.reject { |metric| metric == "page_drift" }).to_h do |metric|
      [metric, result.public_send(metric)]
    end
    unless valid_ratios?(metrics) &&
        %w[pages_official pages_generated].all? { |metric| metrics[metric].is_a?(Integer) && metrics[metric] > 0 }
      raise "invalid extracted metrics or page count"
    end
    metrics["page_drift"] = (result.pages_generated - result.pages_official).abs
    metrics["official_sha256"] = Digest::SHA256.file(official).hexdigest
    errors = differences(metrics, previous)
    row.merge(metrics).merge("status" => errors.empty? ? "pass" : "regression", "errors" => errors,
                             "rows_official" => result.rows_official, "rows_matched" => result.rows_matched,
                             "cells_official" => result.cells_official, "cells_matched" => result.cells_matched)
  rescue StandardError => e
    row.merge("status" => "error", "errors" => [e.message])
  end

  def markdown(rows)
    header = "| Publication | Status | Recall % | Precision % | Order % | Rows matched/official | Rows % | Cells matched/official | Cells % | Pages official/generated | Drift | Details |\n" \
      "|---|---|---|---|---|---|---|---|---|---|---|---|\n"
    header + rows.map do |row|
      fields = [row["key"], row["status"], PdfFidelity.pct(row["recall"]),
                PdfFidelity.pct(row["precision"]), PdfFidelity.pct(row["order"]),
                counts(row, "rows"), PdfFidelity.pct(row["rows"]), counts(row, "cells"),
                PdfFidelity.pct(row["cells"]),
                row.key?("pages_official") ? "#{row['pages_official']}/#{row['pages_generated']}" : "n/a",
                row.fetch("page_drift", "n/a"),
                ([row["official_status"]] + row.fetch("errors")).compact.join("; ")]
      "| #{fields.map { |field| field.to_s.gsub(/[\\|]/) { |character| "\\#{character}" }.gsub(/[\r\n]+/, ' ') }.join(' | ')} |"
    end.join("\n") + "\n"
  end

  def counts(row, metric)
    row.key?("#{metric}_official") ? "#{row["#{metric}_matched"]}/#{row["#{metric}_official"]}" : "n/a"
  end

  def run(root:, generated:, out:, docs: nil, baseline_file:)
    raise ConfigError, "generated directory does not exist: #{generated}" unless File.directory?(generated)

    previous = baseline(baseline_file)
    officials = official_files(root)
    sources = inventory(root, docs)
    # Retain official and baseline coverage even if a source disappeared.
    (previous.keys | officials.keys).each do |key|
      next if docs && !docs.include?("T-SP-#{key[0...-2]}")
      next if sources.any? { |row| row["key"] == key }

      sources << { "key" => key, "source" => nil }
    end
    rows = sources.sort_by { |row| row["key"] }.map do |row|
      compared = compare_row(row, generated, officials[row["key"]], previous[row["key"]])
      if row["source"].nil?
        compared["status"] = "error"
        compared["errors"] << "source missing for official or baseline row"
      end
      compared
    end
    candidate = rows.select { |row| row.key?("official_sha256") }.to_h do |row|
      [row["key"], row.select { |key, _| (RATIOS + PAGES + ["official_sha256"]).include?(key) }]
    end
    FileUtils.mkdir_p(out)
    File.write(File.join(out, "scores.json"), JSON.pretty_generate(rows) + "\n")
    File.write(File.join(out, "scores.md"), markdown(rows))
    File.write(File.join(out, "candidate-baseline.json"), JSON.pretty_generate(candidate) + "\n")
    rows.any? { |row| %w[error regression].include?(row["status"]) } ? 1 : 0
  end

  def main(argv)
    options = { root: File.expand_path("..", __dir__) }
    parser = OptionParser.new do |cli|
      cli.on("--root DIR") { |value| options[:root] = File.expand_path(value) }
      cli.on("--generated DIR") { |value| options[:generated] = File.expand_path(value) }
      cli.on("--out DIR") { |value| options[:out] = File.expand_path(value) }
      cli.on("--docs LIST") { |value| options[:docs] = value.split(",").map(&:strip) }
      cli.on("--baseline FILE") { |value| options[:baseline_file] = File.expand_path(value) }
    end
    parser.parse!(argv)
    raise ConfigError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
    raise ConfigError, "--generated DIR is required" unless options[:generated]

    options[:out] ||= File.join(options[:root], "build/official-comparison")
    options[:baseline_file] ||= File.join(options[:root], "docs/pdf/official-baseline.json")
    run(**options)
  rescue ConfigError, OptionParser::ParseError, SystemCallError => e
    warn "official PDF gate: #{e.message.gsub(/[\r\n]+/, ' ')}"
    2
  end
end

exit OfficialPdfGate.main(ARGV) if $PROGRAM_NAME == __FILE__
