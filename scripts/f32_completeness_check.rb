# frozen_string_literal: true

require 'digest'
require 'json'
require 'fileutils'
require 'optparse'
require_relative '../ituob/lib/ituob/models'
require 'ituob/support'

# Compares captured/recovered rows with the independently parsed print.
module F32CompletenessCheck
  ROOT = File.expand_path('..', __dir__)
  DEFAULT_OUTPUT = File.join(ROOT, 'docs/normalization/f32-completeness-results.adoc')

  def self.generate(candidates_path:, xml_path:, pdf_path:)
    reference = Ituob::Models::F32PrintedList.new(xml_path: xml_path, pdf_path: pdf_path).parse
    raise 'The official printed source was not parsed completely' unless reference.source_complete

    rows = if File.extname(candidates_path) == '.json'
             JSON.parse(File.read(candidates_path))
           else
             Ituob::Support::Yaml.safe_load_file(candidates_path)
           end
    candidates = rows.map do |row|
      Ituob::Models::F32TDIEntry.from_hash(row)
    end
    source = candidates_path.delete_prefix("#{ROOT}/")
    comparison = Ituob::Models::F32CompletenessChecker.new(
      reference: reference, candidates: candidates, candidate_source: source
    ).compare
    render(reference: reference, comparison: comparison, candidate_sha256: Digest::SHA256.file(candidates_path).hexdigest)
  end

  def self.render(reference:, comparison:, candidate_sha256:)
    printed_contexts = reference.contexts.group_by(&:kind).sort.map { |kind, rows| "#{kind}=#{rows.length}" }.join('; ')
    rows = comparison.countries.sort_by(&:country).map do |country|
      "| #{cell(country.country)} | #{country.matching} | #{country.missing} | #{country.extra} | #{country.different}"
    end
    details = %w[missing extra different].flat_map do |kind|
      comparison.public_send(kind).map do |difference|
        [kind.capitalize, difference.country, difference.office_code,
         difference.expected&.telegraph_office_name&.en, difference.actual&.telegraph_office_name&.en,
         difference.reason]
      end
    end
    details.sort_by! { |row| [row[1].to_s, row[2].to_s, row[0], row[3].to_s, row[4].to_s] }
    <<~ADOC
      == Independent printed-list comparison

      Official printed source: #{reference.source_uri}

      Source SHA-256: `#{reference.source_sha256}`

      Source pages: #{reference.pages.length}; printed unique allocations: #{reference.allocations.length}; printed context rows: #{reference.contexts.length}.

      Printed contexts by kind: #{printed_contexts}.

      Candidate source: `#{comparison.candidate_source}`

      Candidate SHA-256: `#{candidate_sha256}`

      Raw recovered rows: #{comparison.candidate_rows}; Recovered context rows: #{comparison.candidate_context_rows} (without an office code).
      Raw rows are not deduplicated or collapsed. Every coded row is compared, including shared indicators and unresolved network-relative offices.
      Printed headings, networks, aliases and names without assigned codes remain source contexts; they are not invented office assignments.
      Assignment identity and normalized English office name are compared by F32CompletenessChecker; multilingual notes and network annotations are not compared.

      Matching: #{comparison.matching_keys.length}; missing: #{comparison.missing.length}; extra: #{comparison.extra.length}; different: #{comparison.different.length}.
      Missing means present in print only; extra means present in the recovered rows only; different means one printed and one recovered name differ for the same assignment.

      == Country totals

      [cols="3,1,1,1,1",options="header"]
      |===
      | Country (French source heading) | Matching | Missing | Extra | Different
      #{rows.join("\n")}
      |===

      == Every missing, extra or different assignment

      [cols="1,2,1,3,3,3",options="header"]
      |===
      | Status | Country | Office code | Printed office name | Recovered office name | Reason
      #{details.map { |row| "| #{row.map { |value| cell(value) }.join(' | ')}" }.join("\n")}
      |===
    ADOC
  end

  def self.cell(value)
    value.to_s.gsub('|', '{vbar}').gsub(/[\r\n]+/, ' ')
  end

  def self.run(arguments)
    options = {
      candidates_path: File.join(ROOT, 'ituob/spec/fixtures/f32/recovered-1214.json'),
      xml_path: File.join(ROOT, 'ituob/spec/fixtures/f32/official-2011.xml'),
      pdf_path: File.join(ROOT, 'ituob/spec/fixtures/f32/official-2011.pdf')
    }
    output = DEFAULT_OUTPUT
    OptionParser.new do |parser|
      parser.banner = 'Usage: ruby scripts/f32_completeness_check.rb [options]'
      parser.on('--candidate PATH', '--candidates PATH', 'Raw recovered F32TDIEntry YAML or JSON rows') do |path|
        options[:candidates_path] = File.expand_path(path)
      end
      parser.on('--xml PATH', 'Positioned XML of the official PDF') { |path| options[:xml_path] = path }
      parser.on('--pdf PATH', 'Pinned official PDF') { |path| options[:pdf_path] = path }
      parser.on('--output PATH', 'AsciiDoc report path, or - for stdout') { |path| output = path }
    end.parse!(arguments)
    raise OptionParser::InvalidArgument, arguments.join(' ') unless arguments.empty?

    report = generate(**options)
    if output == '-'
      $stdout.write(report)
    else
      FileUtils.mkdir_p(File.dirname(output))
      File.write(output, report)
    end
  end
end

F32CompletenessCheck.run(ARGV) if $PROGRAM_NAME == __FILE__
