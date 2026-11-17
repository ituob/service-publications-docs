#!/usr/bin/env ruby
# frozen_string_literal: true

# Poppler measurements, not a visual sign-off. See --help for artifact inputs.
require 'json'
require 'open3'
require 'optparse'
require 'fileutils'
require 'rexml/parsers/pullparser'

module PdfTypesettingReport
  LANGUAGES = %w[en fr es ru zh ar].freeze
  LETTERS = %w[E F S R C A].freeze
  TOFU = /[\uFFFD\u25A1\u25AF\u2610\u0000]/
  BIDI = /[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]/
  BASELINES = File.expand_path('../docs/pdf/typesetting-baselines.json', __dir__)

  class MeasurementError < StandardError; end

  module_function

  def command(*args)
    out, err, status = Open3.capture3(*args)
    raise MeasurementError, "#{args.first}: exit #{status.exitstatus}: #{err.strip}" unless status.success?

    out.force_encoding('UTF-8')
  rescue Errno::ENOENT => e
    raise MeasurementError, e.message
  end

  # NFKC folds Arabic presentation forms into logical letters. Poppler emits
  # directional controls around logical RTL runs: remove controls, never reverse
  # arbitrary strings (which would accept genuinely reversed Arabic text).
  def normalized(text)
    text.unicode_normalize(:nfkc).downcase.gsub(BIDI, '').gsub(/[\p{Z}\s]+/, ' ').strip
  end

  def fonts(pdf)
    command('pdffonts', pdf).lines.drop(2).map do |line|
      match = /\A(.+?)\s+(yes|no)\s+(yes|no)\s+(yes|no)\s+\d+\s+\d+\s*\z/.match(line)
      raise MeasurementError, "pdffonts: unreadable row #{line.strip.inspect}" unless match

      { name: match[1].split.first, embedded: match[2] == 'yes', unicode: match[4] == 'yes' }
    end
  end

  def geometry(pdf)
    info = command('pdfinfo', pdf)
    count = info[/^Pages:\s+(\d+)/, 1].to_i
    raise MeasurementError, 'pdfinfo: no positive page count' unless count.positive?

    pages = command('pdfinfo', '-f', '1', '-l', count.to_s, '-box', pdf)
    sizes = pages.scan(/^Page\s+\d+ size:\s+([\d.]+) x ([\d.]+) pts/).map { |w, h| [w.to_f, h.to_f] }
    rotations = pages.scan(/^Page\s+\d+ rot:\s+(-?\d+)/).flatten.map(&:to_i)
    raise MeasurementError, 'pdfinfo: missing per-page dimensions or rotations' unless sizes.size == count && rotations.size == count

    { count: count, sizes: sizes, rotations: rotations }
  end

  def bounds(pdf)
    # Stream the bbox events: large registers contain hundreds of thousands of
    # words, and retaining a DOM plus repeated XPath scans is prohibitively slow.
    parser = REXML::Parsers::PullParser.new(command('pdftotext', '-bbox', pdf, '-'))
    page_number = 0
    overflow = []
    width = height = nil
    word = nil
    while parser.has_next?
      event = parser.pull
      if event.event_type == :start_element && event[0] == 'page'
        page_number += 1
        width = Float(event[1]['width'])
        height = Float(event[1]['height'])
      elsif event.event_type == :start_element && event[0] == 'word'
        box = %w[xMin yMin xMax yMax].map { |key| Float(event[1][key]) }
        x1, y1, x2, y2 = box
        word = { page: page_number, text: +'', box: box } unless x1 >= -1 && y1 >= -1 && x2 <= width + 1 && y2 <= height + 1
      elsif event.event_type == :text && word
        word[:text] << event[0]
      elsif event.event_type == :end_element && event[0] == 'word'
        overflow << word if word
        word = nil
      end
    end
    raise MeasurementError, 'pdftotext: no bbox pages' if page_number.zero?

    overflow
  rescue REXML::ParseException, ArgumentError, TypeError => e
    raise MeasurementError, "invalid bbox XML: #{e.message}"
  end

  def baseline(entry, baseline_dir, baselines)
    if baseline_dir
      letter = LETTERS[LANGUAGES.index(entry['language'])]
      name = "T-SP-#{entry['standard']}-#{entry['edition_year']}-#{letter}.pdf"
      file = File.join(baseline_dir, name)
      return { pages: geometry(file)[:count], source: file } if File.file?(file)
    end
    key = "#{entry['standard']}-#{entry['edition_year']}/#{entry['language']}"
    baselines[key]&.transform_keys(&:to_sym)
  end

  def roundtrip_reference(entry)
    letter = LETTERS[LANGUAGES.index(entry['language'])]
    stem = "T-SP-#{entry['standard']}-#{entry['edition_year']}"
    sources = Dir[File.expand_path("../documents/#{stem}/*-#{letter}.adoc", __dir__)]
    source = sources.size == 1 ? sources.first : nil
    lines = source ? File.readlines(source, encoding: 'UTF-8') : []
    override = lines.find { |line| line.start_with?(':title: ') }
    heading = lines.find { |line| line.start_with?('= ') }
    title = override ? override.delete_prefix(':title: ').strip : heading&.delete_prefix('= ')&.strip
    title ? [title, source] : [entry['title'].to_s, 'manifest register title']
  end

  def roundtrip_text(text, language)
    value = normalized(text).gsub(/[^\p{L}\p{M}\p{N}]+/, ' ').strip
    # A CJK title may wrap between any two characters without a word boundary.
    language == 'zh' ? value.delete(' ') : value
  end

  def inspect_pdf(entry, file, baseline_dir:, baselines:)
    result = { path: entry['path'], language: entry['language'], failures: [] }
    failures = result[:failures]
    unless File.file?(file) && File.size?(file)
      failures << 'PDF is missing or empty'
      return result
    end
    unless LANGUAGES.include?(entry['language'])
      failures << "unsupported language #{entry['language'].inspect}"
      return result
    end
    checks = {
      fonts: proc do
        result[:fonts] = fonts(file)
        failures << 'no fonts found' if result[:fonts].empty?
        result[:fonts].reject { |font| font[:embedded] }.each { |font| failures << "font not embedded: #{font[:name]}" }
      end,
      text: proc do
        text = command('pdftotext', '-enc', 'UTF-8', file, '-')
        failures << 'extracted text is invalid UTF-8' unless text.valid_encoding?
        text = text.scrub
        failures << 'extracted text is empty' if text.strip.empty?
        bad = text.scan(TOFU).uniq
        failures << "missing-glyph/tofu characters: #{bad.map { |c| format('U+%04X', c.ord) }.join(', ')}" unless bad.empty?
        expected, basis = roundtrip_reference(entry)
        result[:roundtrip] = { expected: expected, basis: basis, matched: !expected.strip.empty? && roundtrip_text(text, entry['language']).include?(roundtrip_text(expected, entry['language'])) }
        failures << "register title did not round-trip: #{expected.inspect}" unless result[:roundtrip][:matched]
        script = { 'ru' => /\p{Cyrillic}/, 'zh' => /\p{Han}/, 'ar' => /\p{Arabic}/ }[entry['language']]
        failures << "no #{entry['language']} script in extracted text" if script && !text.match?(script)
        if script && File.file?(basis) && !expected.match?(script)
          heading = File.foreach(basis, encoding: 'UTF-8').find { |line| line.match?(/\A=+ /) && line.match?(script) }
          sentinel = heading&.sub(/\A=+ /, '')&.strip
          result[:script_roundtrip] = { expected: sentinel, basis: basis, matched: sentinel && roundtrip_text(text, entry['language']).include?(roundtrip_text(sentinel, entry['language'])) }
          failures << "native-script source heading did not round-trip: #{sentinel.inspect}" unless result[:script_roundtrip][:matched]
        end
      end,
      geometry: proc do
        result[:pages] = geometry(file)
        result[:pages][:sizes].each_with_index do |(w, h), i|
          failures << "page #{i + 1}: expected portrait A4, got #{w} x #{h} pt" unless (w - 595.28).abs <= 3 && (h - 841.89).abs <= 3
          failures << "page #{i + 1}: rotated #{result[:pages][:rotations][i]} degrees" unless result[:pages][:rotations][i].zero?
        end
        reference = baseline(entry, baseline_dir, baselines)
        result[:page_count_baseline] = reference || { status: 'n/a', reason: 'no official page-count baseline available' }
        failures << "page count #{result[:pages][:count]} differs from baseline #{reference[:pages]} (#{reference[:source]})" if reference && result[:pages][:count] != reference[:pages]
      end,
      overflow: proc do
        result[:overflow] = bounds(file)
        failures << "text bounding boxes exceed page: #{result[:overflow].size} words" unless result[:overflow].empty?
      end
    }
    checks.each do |name, check|
      check.call
    rescue MeasurementError => e
      failures << "#{name}: #{e.message}"
    end
    result
  end

  def run(pdf_dir:, baseline_dir: nil, progress: nil)
    root = File.expand_path(pdf_dir)
    manifest = [File.join(root, 'pdf', 'manifest.json'), File.join(root, 'manifest.json')].find { |file| File.file?(file) }
    raise MeasurementError, "no manifest.json in #{root} or its pdf directory" unless manifest

    entries = JSON.parse(File.read(manifest)).fetch('publications')
    raise MeasurementError, 'manifest publications must be a nonempty array of mappings' unless entries.is_a?(Array) && !entries.empty? && entries.all?(Hash)

    baselines = JSON.parse(File.read(BASELINES))
    failures = []
    paths = []
    results = entries.map do |entry|
      path = entry['path']
      progress.call(path, paths.size + 1, entries.size) if progress
      unless path.is_a?(String) && path.end_with?('.pdf') && !path.start_with?('/') && path.split('/').none? { |part| ['', '.', '..'].include?(part) } && !path.include?('\\')
        failures << "unsafe or missing manifest path #{path.inspect}"
        next({ path: path, language: entry['language'], failures: ['unsafe or missing manifest path'] })
      end
      file = File.expand_path(path, root)
      # Also accept an artifact unpacked with manifest + publication dirs at root.
      file = File.join(root, path.delete_prefix('pdf/')) unless File.file?(file)
      failures << "duplicate manifest path #{path}" if paths.include?(file)
      paths << file
      inspect_pdf(entry, file, baseline_dir: baseline_dir, baselines: baselines)
    end
    unlisted = Dir[File.join(root, '**', '*')].select { |f| File.file?(f) && File.extname(f).downcase == '.pdf' } - paths
    failures.concat(unlisted.map { |file| "PDF absent from manifest: #{file}" })
    { schema_version: 1, scope: 'Machine measurements only; visual inspection is still required. Bounding boxes cover extracted words; wholly clipped text and non-text graphics may be absent.', manifest: manifest,
      publications: results, failures: failures, passed: failures.empty? && results.all? { |result| result[:failures].empty? } }
  rescue JSON::ParserError, KeyError => e
    raise MeasurementError, "invalid manifest/baseline: #{e.message}"
  end

  def adoc(report)
    summary = report[:publications].group_by { |entry| entry[:language] }.sort.map do |language, entries|
      "|#{language} |#{entries.size} |#{entries.count { |entry| entry[:failures].empty? }} |#{entries.count { |entry| !entry[:failures].empty? }}"
    end
    rows = report[:publications].map do |entry|
      pages = entry.dig(:pages, :count) || 'unmeasured'
      baseline = entry.dig(:page_count_baseline, :pages) || 'n/a'
      "|#{entry[:path]} |#{entry[:language]} |#{entry[:failures].empty? ? 'PASS' : 'FAIL'} |#{pages}/#{baseline} |#{entry[:failures].join('; ').gsub('|', '\\|')}"
    end
    [ '= PDF typesetting measurements', '', report[:scope], '', "Result: #{report[:passed] ? 'PASS' : 'FAIL'}", '',
      '[cols="1,1,1,1",options="header"]', '|===', '|Language |PDFs |Pass |Fail', *summary, '|===', '',
      '[cols="3,1,1,1,5",options="header"]', '|===', '|PDF |Language |Result |Pages/baseline |Failures', *rows, '|===', '',
      *report[:failures].map { |failure| "* #{failure}" }, '' ].join("\n")
  end

  def main(argv)
    options = { pdf_dir: nil, baseline_dir: nil }
    out_dir = 'build/typesetting-report'
    verify = false
    parser = OptionParser.new do |o|
      o.banner = 'Usage: pdf_typesetting_report.rb --pdf-dir ARTIFACT_ROOT [--out-dir DIR] [--baseline-dir DIR] [--verify]'
      o.on('--pdf-dir DIR') { |v| options[:pdf_dir] = v }
      o.on('--baseline-dir DIR') { |v| options[:baseline_dir] = v }
      o.on('--out-dir DIR') { |v| out_dir = v }
      o.on('--verify') { verify = true }
      o.on('--help') { puts o; return 0 }
    end
    extra = parser.parse(argv)
    raise MeasurementError, parser.banner unless options[:pdf_dir] && extra.empty?

    report = run(**options, progress: proc { |path, index, total| warn "Measuring #{index}/#{total}: #{path}" })
    FileUtils.mkdir_p(out_dir)
    File.write(File.join(out_dir, 'report.json'), "#{JSON.pretty_generate(report)}\n")
    File.write(File.join(out_dir, 'report.adoc'), adoc(report))
    puts "#{report[:passed] ? 'PASS' : 'FAIL'}: #{report[:publications].size} PDFs; #{out_dir}/report.json"
    verify && !report[:passed] ? 1 : 0
  rescue MeasurementError, OptionParser::ParseError, SystemCallError => e
    warn "pdf_typesetting_report: #{e.message}"
    2
  end
end

exit(PdfTypesettingReport.main(ARGV)) if $PROGRAM_NAME == __FILE__
