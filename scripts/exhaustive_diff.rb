#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Exhaustive difference analyzer: for every page below 95% coverage,
# dump ALL missing headings, ALL missing tokens (categorized), and
# ALL missing links. No summarization, no shortcuts.

require 'pathname'
require 'yaml'
require 'nokogiri'
require 'set'

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob/auditors/content_parity'
require 'ituob/parity'

DEPLOYED_ROOT = ENV.fetch('DEPLOYED_SITE',
                          File.expand_path('../../.parity-reference/jekyll/_site', __dir__))
LOCAL_ROOT    = ENV.fetch('LOCAL_DIST',
                          File.expand_path('../../ituob.org-v2/dist', __dir__))
OUTPUT_DIR    = ENV.fetch('OUTPUT_DIR',
                          File.expand_path('output/exhaustive_diff', __dir__))

REGISTER_SLUGS = Ituob::Parity::UrlMap::REGISTER_SLUGS

def classify_page(rel_path)
  case rel_path
  when %r{\Aissues/(\d+)-en} then ['issue', $1, File.join(LOCAL_ROOT, 'issues', $1, 'index.html')]
  when %r{\Amessages/complement-to-itu-t-r ([^/]+)/} then ['rec', $1, File.join(LOCAL_ROOT, 'recommendations', $1, 'index.html')]
  when %r{\Amessages/amending-sp ([^/(]+)(?: \([^)]+\))?/}
    slug = REGISTER_SLUGS[$1]
    return nil unless slug
    ['register', slug, File.join(LOCAL_ROOT, 'registers', slug, 'index.html')]
  when 'index.html' then ['index', 'home', File.join(LOCAL_ROOT, 'index.html')]
  else nil
  end
end

def collect_pages
  pages = []
  Pathname.new(DEPLOYED_ROOT).find do |path|
    next unless path.file? && path.to_s.end_with?('index.html')
    next if path.to_s.include?('/assets/')
    pages << path.relative_path_from(DEPLOYED_ROOT).to_s
  end
  pages.sort
end

# Categorize a missing token into a reason bucket.
def categorize_token(token, type, slug)
  if token.match?(/^\d{3,}$/)
    # Numeric token — likely issue number or data value
    num = token.to_i
    if num >= 900 && num <= 1400
      'issue_number'
    elsif num >= 1900 && num <= 2100
      'year'
    else
      'data_value'
    end
  elsif token.match?(/^[A-Z]{2,}$/)
    'country_code_or_acronym'
  elsif ['amd', 'no', 'ob', 'to', 'amendment', 'publication'].include?(token)
    'format_label'
  elsif ['add', 'sup', 'rep', 'lir', 'mod', 'del', 'seed'].include?(token)
    'action_type'
  else
    'content_token'
  end
end

auditor = Ituob::Auditors::ContentParity.new
require 'fileutils'
FileUtils.mkdir_p(OUTPUT_DIR)

# Collect all pages, dedupe by local path
by_local = {}
collect_pages.each do |rel|
  info = classify_page(rel)
  next unless info
  type, key, local_path = info
  deployed_path = File.join(DEPLOYED_ROOT, rel)
  next unless File.file?(deployed_path)

  deployed_html = File.read(deployed_path, encoding: 'utf-8')
  if File.file?(local_path)
    local_html = File.read(local_path, encoding: 'utf-8')
    report = auditor.compare(deployed_html, local_html)
    entry = {
      type: type, key: key, deployed: rel,
      local: local_path.sub(LOCAL_ROOT + '/', ''),
      coverage: report.coverage,
      missing_headings: report.missing_headings,
      missing_tokens: (report.deployed_unique - report.actual_unique).to_a.sort,
      missing_links: report.missing_links.map { |l| l[:href] }.first(20),
      verdict: report.coverage >= 0.95 ? 'pass' : (report.coverage >= 0.80 ? 'warn' : 'fail'),
    }
  else
    entry = { type: type, key: key, deployed: rel, local: nil, coverage: 0.0,
              missing_headings: [], missing_tokens: [], missing_links: [],
              verdict: 'missing' }
  end

  lp = local_path || rel
  if by_local[lp].nil? || entry[:coverage] > by_local[lp][:coverage]
    by_local[lp] = entry
  end
end

# Only analyze non-passing pages
failing = by_local.values.select { |e| e[:verdict] != 'pass' }.sort_by { |e| [e[:type], e[:coverage]] }

puts "Analyzing #{failing.length} non-passing pages in detail..."
puts ""

results = []
failing.each do |entry|
  # Categorize missing tokens
  token_cats = Hash.new(0)
  entry[:missing_tokens].each do |t|
    cat = categorize_token(t, entry[:type], entry[:key])
    token_cats[cat] += 1
  end

  result = entry.merge(token_categories: token_cats)
  results << result

  puts "#{entry[:type]}/#{entry[:key]}: #{(entry[:coverage]*100).round(1)}% (#{entry[:verdict]})"
  puts "  Missing headings (#{entry[:missing_headings].length}):"
  entry[:missing_headings].each { |h| puts "    - #{h.slice(0, 100)}" }
  puts "  Missing tokens by category:"
  token_cats.sort_by { |_, c| -c }.each do |cat, count|
    puts "    #{cat}: #{count}"
  end
  puts "  Sample missing tokens (first 15):"
  entry[:missing_tokens].first(15).each { |t| puts "    - #{t}" }
  puts "  Missing links (#{entry[:missing_links].length}):"
  entry[:missing_links].first(5).each { |l| puts "    - #{l.to_s.slice(0, 80)}" }
  puts ""
end

File.write(File.join(OUTPUT_DIR, 'exhaustive_diff.yaml'), results.to_yaml)

# Aggregate
puts ""
puts "=== AGGREGATE ==="
all_token_cats = Hash.new(0)
results.each { |r| r[:token_categories].each { |cat, count| all_token_cats[cat] += count } }
puts "Total missing tokens by category:"
all_token_cats.sort_by { |_, c| -c }.each do |cat, count|
  puts "  #{cat}: #{count}"
end

puts ""
puts "Total missing headings by type:"
heading_counts = Hash.new(0)
results.each { |r| heading_counts[r[:type]] += r[:missing_headings].length }
heading_counts.each { |type, count| puts "  #{type}: #{count}" }

puts ""
puts "Report: #{OUTPUT_DIR}/exhaustive_diff.yaml"
