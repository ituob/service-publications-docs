#!/usr/bin/env ruby
# frozen_string_literal: true
# Full content-parity audit: walks every HTML page in the deployed
# Jekyll site, finds its counterpart on the new Astro site, and runs
# Ituob::Auditors::ContentParity against the pair.
#
# ROLE: per-page YAML detail dump (best-variant mapping). Superseded
# as the parity GATE by scripts/parity_report.rb (worst-variant rule —
# this script's best-variant mapping masks multi-variant gaps). Use it
# for per-page detail inspection only; verdicts come from parity_report.

require 'pathname'
require 'fileutils'
require 'json'
require 'yaml'
require 'optparse'

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob/auditors/content_parity'

DEPLOYED_ROOT = ENV.fetch('DEPLOYED_SITE',
                          File.expand_path('../ituob.org/_site', __dir__))
LOCAL_ROOT    = ENV.fetch('LOCAL_DIST',
                          File.expand_path('../ituob.org-v2/dist', __dir__))
OUTPUT_DIR    = ENV.fetch('OUTPUT_DIR',
                          File.expand_path('../service-publications-docs/scripts/output/parity_full', __dir__))

# Map a deployed register ID to its Astro slug.
REGISTER_SLUGS = {
  'E118_IIN' => 'e118-iin',
  'DP' => 'dp',
  'E164_ACN' => 'e164-acn',
  'E164_CC' => 'e164-cc',
  'E212_MNC' => 'e212-mnc',
  'E212_ICC' => 'e212-icc',
  'E218_TRCC' => 'e218-trcc',
  'F1' => 'f1',
  'F32_TDI' => 'f32-tdi',
  'BUREAUFAX' => 'bureaufax',
  'F400_ADMD' => 'f400-admd',
  'M1400_ICC' => 'm1400-icc',
  'Q708_ISPC' => 'q708-ispc',
  'Q708_SANC' => 'q708-sanc',
  'T35_NA' => 't35-na',
  'T35_CC' => 't35-cc',
  'X121_DNIC' => 'x121-dnic',
  'RR.25.1' => 'rr251',
  'NNP' => 'nnp',
}.freeze

# Parse an ISO date or datetime string from a deployed URL fragment.
# Returns Date or nil.
def parse_url_date(str)
  return nil if str.nil? || str == '-'

  str = str.sub(/ \d{2}:\d{2}(:\d{2})?( UTC)?\z/, '')
  Date.parse(str) rescue nil
end

# Find a deployed register's amending-sp directories (one per snapshot date)
# and map each to a /registers/{slug}/at/{N}/ counterpart.
def amending_sp_pairs(deployed_messages_dir, local_registers_dir)
  pairs = []
  Dir.children(deployed_messages_dir)
     .select { |n| n.start_with?('amending-sp ') }
     .each do |dir|
    register_id = dir.sub(/\Aamending-sp /, '')
                    .sub(/ \([^)]+\)\z/, '')
                    .sub(/ \(-\)\z/, '')
    slug = REGISTER_SLUGS[register_id]
    next unless slug

    # Each year subdir has index.html — those are the actual snapshot pages
    dir_path = File.join(deployed_messages_dir, dir)
    Dir.children(dir_path).each do |sub|
      next unless sub =~ /\A\d{4}\z/

      year_dir = File.join(dir_path, sub)
      Dir.children(year_dir)
        .select { |n| n =~ /\A\d+-en\z/ }
        .each do |issue_dir|
        deployed_path = File.join(year_dir, issue_dir, 'index.html')
        next unless File.file?(deployed_path)

        ob_issue = issue_dir.sub(/-en\z/, '')
        local_path = File.join(local_registers_dir, slug, 'at', ob_issue, 'index.html')
        pairs << [deployed_path, local_path, "register/#{slug}/at/#{ob_issue}"]
      end
    end

    # The top-level index.html is the register landing page
    top = File.join(dir_path, 'index.html')
    if File.file?(top)
      local = File.join(local_registers_dir, slug, 'index.html')
      pairs << [top, local, "register/#{slug}"]
    end
  end
  pairs
end

def complement_pairs(deployed_messages_dir, local_recs_dir)
  pairs = []
  Dir.children(deployed_messages_dir)
     .select { |n| n.start_with?('complement-to-itu-t-r ') }
     .each do |dir|
    rec_code = dir.sub(/\Acomplement-to-itu-t-r /, '')
    deployed_path = File.join(deployed_messages_dir, dir, 'index.html')

    # Astro recommendation URL = /recommendations/{code}/
    # The new site directory name uses dots/dots verbatim
    local_path = File.join(local_recs_dir, rec_code, 'index.html')
    pairs << [deployed_path, local_path, "recommendation/#{rec_code}"] if File.file?(deployed_path)
  end
  pairs
end

def issue_pairs(deployed_issues_dir, local_issues_dir)
  pairs = []
  Dir.children(deployed_issues_dir)
     .select { |n| n =~ /\A\d+-en\z/ }
     .each do |dir|
    id = dir.sub(/-en\z/, '')
    deployed = File.join(deployed_issues_dir, dir, 'index.html')
    local = File.join(local_issues_dir, id, 'index.html')
    pairs << [deployed, local, "issue/#{id}"]
  end
  pairs
end

def top_level_pairs(deployed_root, local_root)
  pairs = []
  [['index.html', 'index.html'], ['404.html', '404.html']].each do |d, l|
    dp = File.join(deployed_root, d)
    lp = File.join(local_root, l)
    pairs << [dp, lp, d] if File.file?(dp)
  end
  pairs
end

def run
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename($0)} [options]"
    opts.on('--sample N', Integer, 'Only audit N pages of each type') { |v| options[:sample] = v }
    opts.on('--type TYPE', String, 'Only audit TYPE (issues|registers|recommendations|top)') { |v| options[:type] = v }
  end.parse!

  FileUtils.mkdir_p(OUTPUT_DIR)
  auditor = Ituob::Auditors::ContentParity.new

  pairs = []
  pairs.concat(top_level_pairs(DEPLOYED_ROOT, LOCAL_ROOT)) unless options[:type] && options[:type] != 'top'
  pairs.concat(issue_pairs(File.join(DEPLOYED_ROOT, 'issues'),
                           File.join(LOCAL_ROOT, 'issues'))) unless options[:type] && options[:type] != 'issues'
  pairs.concat(complement_pairs(File.join(DEPLOYED_ROOT, 'messages'),
                                File.join(LOCAL_ROOT, 'recommendations'))) unless options[:type] && options[:type] != 'recommendations'
  pairs.concat(amending_sp_pairs(File.join(DEPLOYED_ROOT, 'messages'),
                                 File.join(LOCAL_ROOT, 'registers'))) unless options[:type] && options[:type] != 'registers'

  if options[:sample]
    grouped = pairs.group_by { |_, _, label| label.split('/').first }
    sampled = grouped.flat_map do |_, arr|
      arr.sort_by { |_, _, _| rand }.first(options[:sample])
    end
    pairs = sampled
  end

  puts "Auditing #{pairs.length} page pairs..."
  puts "  deployed: #{DEPLOYED_ROOT}"
  puts "  local:    #{LOCAL_ROOT}"

  results = []
  pairs.each_with_index do |(deployed_path, local_path, label), idx|
    unless File.file?(deployed_path)
      warn "skip #{label}: deployed missing"
      next
    end

    deployed_html = File.read(deployed_path, encoding: 'utf-8')

    if File.file?(local_path)
      local_html = File.read(local_path, encoding: 'utf-8')
      report = auditor.compare(deployed_html, local_html)
      results << {
        label: label,
        deployed_path: deployed_path.sub(DEPLOYED_ROOT + '/', ''),
        local_path: local_path.sub(LOCAL_ROOT + '/', ''),
        coverage: report.coverage.round(4),
        deployed_tokens: report.deployed_tokens,
        actual_tokens: report.actual_tokens,
        missing_headings: report.missing_headings,
        missing_links_count: report.missing_links.length,
        missing_tables: report.missing_tables,
        sections_below_threshold: report.sections.count { |s| s.coverage < 0.9 },
      }
    else
      # Page exists on deployed but not on local — significant gap
      results << {
        label: label,
        deployed_path: deployed_path.sub(DEPLOYED_ROOT + '/', ''),
        local_path: nil,
        coverage: 0.0,
        deployed_tokens: 0,
        actual_tokens: 0,
        missing_headings: [],
        missing_links_count: 0,
        missing_tables: [],
        sections_below_threshold: 0,
        missing_local: true,
      }
    end

    if (idx + 1) % 50 == 0
      puts "  #{idx + 1}/#{pairs.length}..."
    end
  end

  # Write per-page reports
  File.write(File.join(OUTPUT_DIR, 'all_pages.yaml'), results.to_yaml)

  # Summary
  by_type = results.group_by { |r| r[:label].split('/').first }
  summary = {}
  by_type.each do |type, arr|
    coverage_avg = arr.sum { |r| r[:coverage] } / [arr.length, 1].max
    missing_local = arr.count { |r| r[:missing_local] }
    summary[type] = {
      pages: arr.length,
      avg_coverage: coverage_avg.round(4),
      missing_local_count: missing_local,
      worst: arr.reject { |r| r[:missing_local] }
               .min_by(5) { |r| r[:coverage] }
               .map { |r| { label: r[:label], coverage: r[:coverage],
                            missing_headings: r[:missing_headings].length,
                            missing_links: r[:missing_links_count],
                            missing_tables: r[:missing_tables].length } },
    }
  end
  File.write(File.join(OUTPUT_DIR, 'summary.yaml'), summary.to_yaml)

  puts ""
  puts "==== SUMMARY ===="
  summary.each do |type, s|
    puts "#{type}: #{s[:pages]} pages, avg #{format('%.1f%%', s[:avg_coverage] * 100)}, #{s[:missing_local_count]} missing locally"
    s[:worst].each do |w|
      puts "    #{w[:label]}: #{format('%.1f%%', w[:coverage] * 100)} (H=#{w[:missing_headings]} L=#{w[:missing_links]} T=#{w[:missing_tables]})"
    end
  end

  puts ""
  puts "Per-page reports: #{OUTPUT_DIR}/all_pages.yaml"
  puts "Summary:          #{OUTPUT_DIR}/summary.yaml"
end

run if __FILE__ == $PROGRAM_NAME
