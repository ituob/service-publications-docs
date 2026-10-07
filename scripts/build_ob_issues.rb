#!/usr/bin/env ruby
# frozen_string_literal: true
# build_ob_issues.rb
#
# Reads OB issue source data from itu-ob-data/issues/{id}/, runs the ituob gem
# parsers, and writes the normalized per-issue directory tree to
# service-publications-docs/ob-issues/{id}/.
#
# Output shape per TODO.new-structure/03:
#
#   ob-issues/{issue-no}/
#     meta.yaml
#     annexes.yaml
#     {dataset-name}/
#       {NNN}-{ADD|REP|SUP}.yaml      # structured change object
#       text.yaml                      # for TextAmendment types
#     {text-dataset-name}/
#       {NNN}.yaml                     # freeform ProseMirror content
#     general/
#       running-annexes.yaml

require 'prosereflect'
$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'

# ...
#       approved-recommendations.yaml
#
# The script is idempotent — re-running it overwrites prior output identically.

require 'yaml'
require 'fileutils'
require 'pathname'

# Load the ituob gem from this same repository
ITUIOB_GEM_PATH = File.expand_path('../ituob/lib', __dir__)
$LOAD_PATH.unshift(ITUIOB_GEM_PATH) if File.directory?(ITUIOB_GEM_PATH)

require 'ituob'

ITU_OB_DATA_ROOT = ENV.fetch('ITU_OB_DATA_ROOT') {
  File.expand_path('../itu-ob-data', __dir__)
}
ITU_OB_DATA_PATH = File.join(ITU_OB_DATA_ROOT, 'issues')
OB_ISSUES_OUT_PATH = ENV.fetch('OB_ISSUES_OUT_PATH') {
  File.expand_path('../ob-issues', __dir__)
}

# Map OB publication identifiers to filesystem-safe dataset names.
DATASET_SLUG_BY_PUBLICATION = {
  'E118_IIN' => 'e118-iin',
  'DP' => 'dp',
  'E164_ACN' => 'e164-acn',
  'E164_CC' => 'e164-cc',
  'E212_ICC' => 'e212-icc',
  'E212_MNC' => 'e212-mnc',
  'E218_TRCC' => 'e218-trcc',
  'F32_TDI' => 'f32-tdi',
  'F400_ADMD' => 'f400-admd',
  'M1400_ICC' => 'm1400-icc',
  'Q708_ISPC' => 'q708-ispc',
  'Q708_SANC' => 'q708-sanc',
  'T35_NA' => 't35-na',
  'X121_DNIC' => 'x121-dnic',
  'RR.25.1' => 'rr251',
  'BUREAUFAX' => 'bureaufax',
  'List of Coast Stations and Special Service Stations' => 'coast-stations',
  'R_SP_LM.V' => 'list-v',
  'R_SP_LN.VIII' => 'list-viii',
  'NNP' => 'nnp',
}

# General message types that are freeform and bucket by type name.
TEXTUAL_GENERAL_TYPES = %w[
  sanc
  iptn
  ipns
  mid
  org_changes
  misc_communications
  service_restrictions
  custom
  callback_procedures
  telephone_service_2
  telephone_service
].freeze

# General message types that get their own structured file under general/.
STRUCTURED_GENERAL_TYPES = %w[
  running_annexes
  approved_recommendations
].freeze

def issue_source_dirs
  Dir.children(ITU_OB_DATA_PATH).select { |n| n =~ /\A\d+\z/ }.sort_by(&:to_i)
end

def write_yaml(path, data)
  FileUtils.mkdir_p(File.dirname(path))
  payload = YAML.dump(data)
  payload.sub!(/\A---\n/, '')
  File.write(path, payload)
end

def copy_meta_and_annexes(issue_id, src_dir, dst_dir)
  %w[meta.yaml annexes.yaml].each do |fname|
    src = File.join(src_dir, fname)
    next unless File.file?(src)
    dst = File.join(dst_dir, fname)
    FileUtils.cp(src, dst)

    # Mark known-incomplete issues. The deployed Jekyll site flags
    # these specific issues as "data below may not be complete yet."
    if fname == 'meta.yaml' && [669, 1075].include?(issue_id)
      content = File.read(dst)
      unless content.match?(/^incomplete:/)
        lines = content.split("\n")
        lines.insert(1, "incomplete: true")
        File.write(dst, lines.join("\n"))
      end
    end
  end
end

def write_change_object(issue_id:, dataset_slug:, seq:, type: 'ADD',
                        date_active:, identifier:, data:, description: nil)
  obj = {
    'type' => type,
    'date_requested' => date_active,
    'date_active' => date_active,
    'ob_issue_no' => issue_id.to_s,
    'reference' => "OB-#{issue_id}",
    'identifier' => identifier,
    'data' => data,
  }
  obj['description'] = description if description
  obj
end

def slug_for_publication(pub_id)
  DATASET_SLUG_BY_PUBLICATION.fetch(pub_id) { pub_id.downcase.gsub(/[^a-z0-9.]+/, '-') }
end

def process_amendments(issue_id, src_dir, dst_dir, stats)
  path = File.join(src_dir, 'amendments.yaml')
  return unless File.file?(path)
  data = YAML.load_file(path, permitted_classes: [Date, Time])
  return unless data.is_a?(Hash) && data['messages'].is_a?(Array)

  data['messages'].each do |msg|
    next unless msg['type'] == 'amendment'
    next unless msg['target'] && msg['target']['publication']

    pub_id = msg['target']['publication']
    dataset_slug = slug_for_publication(pub_id)
    position_on = msg['target']['position_on']

    contents_en = msg.dig('contents', 'en')
    unless contents_en
      stats[:skipped_no_content] += 1
      next
    end

    # Try parsing as a structured amendment via the ituob gem.
    parsed = nil
    parse_error = nil
    klass = Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS[pub_id]
    if klass
      begin
        parsed = klass.parse(contents_en, position_on: position_on, dataset_code: pub_id)
      rescue => e
        parse_error = "#{e.class}: #{e.message}"
      end
    end

    # Generic trailing-glossary-note extraction. Catches the
    # trilingual notes ("MCC:", "ISPC:", "SANC:", "IIN:",
    # "Notes common to...", "Codes de points...") that many
    # amendments end with. Per-parser note extraction takes
    # precedence; this fills in parsers that haven't been updated.
    if parsed.is_a?(Ituob::Models::Amendment)
      current_notes = parsed.notes || []
      if !current_notes.is_a?(Array) || current_notes.empty?
        doc = Prosereflect::Parser.parse_document(contents_en)
        simplified = Ituob::Helpers.dump_doc(doc)
        generic_notes = []
        simplified.each do |c|
          next unless c.is_a?(Array)
          next unless c[0].is_a?(String)
          text = Ituob::Helpers.replace_legacy_space(c.join(' ')).strip
          # Glossary-like: "MCC:", "ISPC:", "SANC:", "IIN:", "T.35:",
          # or paragraphs starting with capital letter(s) ending in a
          # period that contain trilingual indicators (FR/ES keywords).
          if text.match?(/^[A-Z]{2,5}:/) ||
             text.match?(/^Codes de/) ||
             text.match?(/^Códigos de/) ||
             text.match?(/^Notes common/) ||
             text.match?(/^_{3,}/) ||
             text.match?(/^See page/) ||
             text.match?(/^[a-z]\. /) ||
             (text.length > 30 && text.match?(/Mobile Country Code/) || text.match?(/International Signalling/))
            generic_notes << text unless text.empty?
          end
        end
        parsed.notes = generic_notes if generic_notes.any?
      end
    end

    dataset_dir = File.join(dst_dir, dataset_slug)
    FileUtils.mkdir_p(dataset_dir)

    if parsed && parsed.is_a?(Ituob::Models::Amendment) &&
       parsed.class.attributes.key?(:actions) && parsed.actions.any?
      parsed.actions.each_with_index do |action, idx|
        seq_str = format('%03d', idx + 1)
        attrs = action.class.attributes
        action_type = attrs.key?(:action_type) ? action.action_type : 'ADD'
        # Normalize action type to uppercase alphanumeric so the
        # filename matches the Astro loader's ACTION_RE pattern
        # (/^(\d+)-([A-Z0-9]+)$/). Non-standard types like "by:"
        # default to "ADD".
        normalized_type = (action_type || 'ADD').to_s
        normalized_type = 'ADD' unless normalized_type.match?(/\A[A-Z][A-Z0-9]*\z/)
        slug = "#{seq_str}-#{normalized_type}"
        entries_data = if attrs.key?(:entries) && action.entries.any?
                         action.entries.map { |e| e.is_a?(Lutaml::Model::Serializable) ? e.to_hash : e }
                       else
                         []
                       end
        action_label = nil
        action_label = action.position.to_s if attrs.key?(:position) && action.position
        action_label ||= action.order.to_s if attrs.key?(:order) && action.order
        identifier = action_label ?
                       { 'code' => action_label } :
                       { 'code' => "#{issue_id}-#{seq_str}" }
        description = attrs.key?(:description) ? action.description : nil
        change = write_change_object(
          issue_id: issue_id,
          dataset_slug: dataset_slug,
          seq: seq_str,
          type: action_type || 'ADD',
          date_active: position_on,
          identifier: identifier,
          data: {
            '_class' => parsed.class.name.split('::').last,
            'position' => attrs.key?(:position) ? action.position : nil,
            'country' => attrs.key?(:country) ? action.country : nil,
            'description' => description,
            'caption' => attrs.key?(:caption) ? action.caption : nil,
            'entries' => entries_data,
            'notes' => parsed.notes || [],
          }.compact,
        )
        write_yaml(File.join(dataset_dir, "#{slug}.yaml"), change)
        stats[:actions_written] += 1
      end
      stats[:by_amendment_target][pub_id][:structured] += 1
    else
      # TextAmendment or no parser available — store verbatim as text.yaml.
      text_payload = {
        '_class' => (parsed&.class&.name || 'TextAmendment').split('::').last,
        'ob_issue_no' => issue_id.to_s,
        'reference' => "OB-#{issue_id}",
        'position_on' => position_on,
        'contents' => contents_en,
        'parse_error' => parse_error,
      }.compact
      write_yaml(File.join(dataset_dir, 'text.yaml'), text_payload)
      stats[:text_written] += 1
      stats[:by_amendment_target][pub_id][:text] += 1
      stats[:parse_errors] += 1 if parse_error
      stats[:by_amendment_target][pub_id][:errors] += 1 if parse_error
    end
  end
end

def process_general(issue_id, src_dir, dst_dir, stats)
  path = File.join(src_dir, 'general.yaml')
  return unless File.file?(path)
  data = YAML.load_file(path, permitted_classes: [Date, Time])
  return unless data.is_a?(Hash) && data['messages'].is_a?(Array)

  # Always create the general/ directory, even when there are no messages.
  # The auditor and renderer expect the directory to exist; an empty issue
  # is still "complete" from a structural standpoint.
  general_dir = File.join(dst_dir, 'general')
  FileUtils.mkdir_p(general_dir)

  data['messages'].each do |msg|
    type = msg['type'] || 'no_type'
    contents = msg['content'] || msg['contents']

    if STRUCTURED_GENERAL_TYPES.include?(type)
      out_dir = File.join(dst_dir, 'general')
      FileUtils.mkdir_p(out_dir)
      payload = {
        'ob_issue_no' => issue_id.to_s,
        'type' => type,
        'payload' => msg.reject { |k, _| k == 'type' },
      }
      write_yaml(File.join(out_dir, "#{type}.yaml"), payload)
      stats[:general_structured] += 1
      stats[:by_general_type][type] += 1
    elsif TEXTUAL_GENERAL_TYPES.include?(type) || type == 'no_type'
      out_dir = File.join(dst_dir, type)
      FileUtils.mkdir_p(out_dir)
      idx = Dir.children(out_dir).length + 1
      # Preserve every field from the source message (items, payload,
      # title, by, procedures, etc.) so renderers can specialize per
      # type without losing data.
      payload = msg.merge('ob_issue_no' => issue_id.to_s)
      write_yaml(File.join(out_dir, format('%03d.yaml', idx)), payload)
      stats[:general_textual] += 1
      stats[:by_general_type][type] += 1
    else
      stats[:general_unknown_type] += 1
      stats[:by_general_type]["unknown:#{type}"] += 1
    end
  end
end

def process_issue(issue_id, stats)
  src_dir = File.join(ITU_OB_DATA_PATH, issue_id.to_s)
  return unless File.directory?(src_dir)

  dst_dir = File.join(OB_ISSUES_OUT_PATH, issue_id.to_s)
  FileUtils.rm_rf(dst_dir)
  FileUtils.mkdir_p(dst_dir)

  copy_meta_and_annexes(issue_id, src_dir, dst_dir)
  process_amendments(issue_id, src_dir, dst_dir, stats)
  process_general(issue_id, src_dir, dst_dir, stats)
  stats[:issues_processed] += 1
rescue => e
  stats[:issues_failed] += 1
  warn "FAIL #{issue_id}: #{e.class}: #{e.message}"
  warn e.backtrace.first(5).join("\n")
end

def main
  FileUtils.mkdir_p(OB_ISSUES_OUT_PATH)
  stats = Hash.new(0)
  stats[:actions_written] = 0
  stats[:text_written] = 0
  stats[:general_structured] = 0
  stats[:general_textual] = 0
  stats[:general_unknown_type] = 0
  stats[:issues_processed] = 0
  stats[:issues_failed] = 0
  stats[:skipped_no_content] = 0
  stats[:parse_errors] = 0
  # Per-parsing-class breakdown so we can see which parsers produced structured
  # output vs. fell back to TextAmendment.
  stats[:by_amendment_target] = Hash.new { |h, k| h[k] = { structured: 0, text: 0, errors: 0 } }
  stats[:by_general_type] = Hash.new { |h, k| h[k] = 0 }

  # inject the by_* counters into process_* by stashing them in a thread-local
  Thread.current[:build_stats] = stats

  ids = issue_source_dirs
  # Allow limiting via ISSUE_SAMPLE=N env var for testing.
  if ENV['ISSUE_SAMPLE']
    ids = ids.first(ENV['ISSUE_SAMPLE'].to_i)
  end
  # Regenerate a specific subset: ISSUE_IDS=957,963 bundle exec ruby ...
  partial = false
  if ENV['ISSUE_IDS']
    wanted = ENV['ISSUE_IDS'].split(',').map(&:strip)
    ids = ids.select { |id| wanted.include?(id.to_s) }
    partial = true
  end
  ids.each { |id| process_issue(id, stats) }

  unless partial
    manifest = {
      'generated_at' => Time.now.utc.iso8601,
      'itu_ob_data_path' => ITU_OB_DATA_PATH,
      'ob_issues_path' => OB_ISSUES_OUT_PATH,
      'issue_count' => ids.size,
      'stats' => stats,
    }
    write_yaml(File.join(OB_ISSUES_OUT_PATH, 'manifest.yaml'), manifest)

    # Also write a parser-coverage report keyed off the same stats.
    coverage = {
      'generated_at' => Time.now.utc.iso8601,
      'amendment_parsers' => stats[:by_amendment_target],
      'general_parsers' => stats[:by_general_type],
      'totals' => {
        'actions_written' => stats[:actions_written],
        'text_written' => stats[:text_written],
        'general_structured' => stats[:general_structured],
        'general_textual' => stats[:general_textual],
        'parse_errors' => stats[:parse_errors],
      },
    }
    out_dir = File.expand_path('../scripts/output', __dir__)
    FileUtils.mkdir_p(out_dir)
    write_yaml(File.join(out_dir, 'parser-coverage-report.yaml'), coverage)
  end
  puts stats.inspect
end

require 'time'
main
