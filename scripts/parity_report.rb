#!/usr/bin/env ruby
# frozen_string_literal: true
# parity_report.rb — THE parity gate (canonical).
#
# Worst-variant rule: a page passes only when EVERY deployed Jekyll
# variant of it passes >=95%. Cross-listed pages (a Jekyll quirk that
# embeds another register's annex) are recorded as documented anomalies
# and excluded from verdicts — their content renders on the owning
# register's page. See CROSS_LISTED_PAGES below.
#
# Page-by-page validation report. Walks every page on the deployed
# Jekyll reference, finds its counterpart on the new Astro build,
# and emits a human-readable Markdown report showing per-page
# pass/fail with specific gap details.

require 'pathname'
require 'fileutils'
require 'json'
require 'yaml'
require 'nokogiri'

require_relative File.expand_path('../ituob/lib/ituob/auditors/content_parity', __dir__)

DEPLOYED_ROOT = ENV.fetch('DEPLOYED_SITE',
                          File.expand_path('../../.parity-reference/jekyll/_site', __dir__))
LOCAL_ROOT    = ENV.fetch('LOCAL_DIST',
                          File.expand_path('../../ituob.org-v2/dist', __dir__))
OUTPUT_DIR    = ENV.fetch('OUTPUT_DIR',
                          File.expand_path('../scripts/output', __dir__))

REGISTER_SLUGS = {
  'E118_IIN' => 'e118-iin', 'DP' => 'dp', 'E164_ACN' => 'e164-acn',
  'E164_CC' => 'e164-cc', 'E212_MNC' => 'e212-mnc', 'E212_ICC' => 'e212-icc',
  'E218_TRCC' => 'e218-trcc', 'F1' => 'f1', 'F32_TDI' => 'f32-tdi',
  'BUREAUFAX' => 'bureaufax', 'F400_ADMD' => 'f400-admd',
  'M1400_ICC' => 'm1400-icc', 'Q708_ISPC' => 'q708-ispc',
  'Q708_SANC' => 'q708-sanc', 'T35_NA' => 't35-na', 'T35_CC' => 't35-cc',
  'X121_DNIC' => 'x121-dnic', 'RR.25.1' => 'rr251', 'NNP' => 'nnp',
  'List of Coast Stations and Special Service Stations' => 'coast-stations',
  'R_SP_LM.V' => 'list-v', 'R_SP_LN.VIII' => 'list-viii',
}.freeze

# Categorize a deployed URL into a page type + local counterpart.
def classify_page(rel_path)
  # rel_path looks like 'issues/1234-en/index.html',
  # 'messages/complement-to-itu-t-r E.118/index.html', etc.
  case rel_path
  when %r{\Aissues/(\d+)-en/index\.html\z}
    id = Regexp.last_match(1)
    ["issue/#{id}", File.join(LOCAL_ROOT, 'issues', id, 'index.html'), "Issue #{id}"]
  when %r{\Aissues/(\d+)-en/(\d+)/index\.html\z}
    # Year subdirectory of an issue — Astro collapses these
    id = Regexp.last_match(1)
    ["issue/#{id}", File.join(LOCAL_ROOT, 'issues', id, 'index.html'), "Issue #{id}"]
  when %r{\Amessages/complement-to-itu-t-r ([^/]+)/index\.html\z}
    rec = Regexp.last_match(1)
    ["recommendation/#{rec}", File.join(LOCAL_ROOT, 'recommendations', rec, 'index.html'), "Rec #{rec}"]
  when %r{\Amessages/complement-to-itu-t-r ([^/]+)/\d{4}/index\.html\z}
    rec = Regexp.last_match(1)
    ["recommendation/#{rec}", File.join(LOCAL_ROOT, 'recommendations', rec, 'index.html'), "Rec #{rec} (year subpage)"]
  when %r{\Amessages/amending-sp ([^/(]+)(?: \([^)]+\))?/index\.html\z}
    register_id = Regexp.last_match(1)
    slug = REGISTER_SLUGS[register_id]
    return nil unless slug

    ["register/#{slug}", File.join(LOCAL_ROOT, 'registers', slug, 'index.html'), "Register #{slug}"]
  when %r{\Amessages/amending-sp ([^/(]+)(?: \([^)]+\))?/\d{4}/[^/]+/index\.html\z}
    # Year+issue subdirectory of a register page
    register_id = Regexp.last_match(1)
    slug = REGISTER_SLUGS[register_id]
    return nil unless slug

    issue_match = rel_path.match(%r{/(\d+)-en/index\.html\z})
    return nil unless issue_match

    issue = issue_match[1]
    ["register/#{slug}/at/#{issue}", File.join(LOCAL_ROOT, 'registers', slug, 'at', issue, 'index.html'),
     "Register #{slug} @ OB #{issue}"]
  when 'index.html'
    ['index', File.join(LOCAL_ROOT, 'index.html'), 'Homepage']
  when '404.html'
    ['404', File.join(LOCAL_ROOT, '404.html'), '404 page']
  when %r{\A(docs|_app_help)/.*index\.html\z}
    # Editor docs — Astro doesn't mirror
    nil
  else
    # Unknown page type — skip silently
    nil
  end
end

# Deployed pages that embed another register's annex content — a
# co-location quirk of the Jekyll generator. Keyed by exact deployed
# rel-path; value is the explanation. The embedded content IS rendered
# on the owning register's page (verified token-by-token); duplicating
# it here would break per-register attribution.
CROSS_LISTED_PAGES = {
  'messages/amending-sp F32_TDI (2011-04-15)/index.html' =>
    'embeds the full OB-1000 BUREAUFAX annex (PARTIE II/III/V fax-booth ' \
    'tables); rendered at /registers/bureaufax/',
  'messages/complement-to-itu-t-r F.32/2012/index.html' =>
    'embeds the full OB-1000 BUREAUFAX annex (PARTIE II/III/V fax-booth ' \
    'tables); rendered at /registers/bureaufax/',
}.freeze

def collect_deployed_pages
  pages = []
  Pathname.new(DEPLOYED_ROOT).find do |path|
    next unless path.file?
    next unless path.to_s.end_with?('index.html')
    next if path.to_s.include?('/assets/')

    rel = path.relative_path_from(DEPLOYED_ROOT).to_s
    pages << rel
  end
  pages.sort
end

def run
  FileUtils.mkdir_p(OUTPUT_DIR)
  auditor = Ituob::Auditors::ContentParity.new
  deployed_pages = collect_deployed_pages

  # Dedupe by local_path so we don't count year-subpage duplicates.
  # Multiple Jekyll URLs (year subpages) map to the same Astro page.
  by_local = {}
  cross_listed = []
  deployed_pages.each do |rel|
    label, local_path, human = classify_page(rel)
    next unless label

    deployed_path = File.join(DEPLOYED_ROOT, rel)
    deployed_html = File.read(deployed_path, encoding: 'utf-8')

    entry = if File.file?(local_path)
              local_html = File.read(local_path, encoding: 'utf-8')
              report = auditor.compare(deployed_html, local_html)
              {
                label: label,
                human: human,
                deployed: rel,
                local: local_path.sub(LOCAL_ROOT + '/', ''),
                coverage: report.coverage,
                missing_headings: report.missing_headings,
                missing_links_count: report.missing_links.length,
                missing_tables: report.missing_tables,
                verdict: report.coverage >= 0.95 ? 'pass' : (report.coverage >= 0.80 ? 'warn' : 'fail'),
              }
            else
              {
                label: label,
                human: human,
                deployed: rel,
                local: nil,
                coverage: 0.0,
                missing_headings: [],
                missing_links_count: 0,
                missing_tables: [],
                verdict: 'missing',
              }
            end

    # Deployed pages that embed another register's annex content (a
    # Jekyll generator co-location quirk). We render that content on
    # the OWNING register's page — duplicating a foreign register's
    # annex here would violate per-register attribution. Recorded as
    # a documented anomaly, excluded from pass/fail verdicts.
    if (note = CROSS_LISTED_PAGES[rel])
      entry[:verdict] = 'cross-listed'
      entry[:cross_listed_note] = note
      cross_listed << entry
      next
    end

    # Keep the LOWEST-coverage entry per local page: a page passes only
    # when EVERY deployed variant of it passes. (Keeping the best
    # variant masked real gaps — register f32-tdi's canonical page sat
    # at 84% while a year variant hit 99%.)
    key = local_path || label
    if by_local[key].nil?
      entry[:variant_count] = 1
      by_local[key] = entry
    else
      entry[:variant_count] = by_local[key][:variant_count] + 1
      by_local[key] = entry if entry[:coverage] < by_local[key][:coverage]
    end
  end

  # Bucket pages by type
  results = Hash.new { |h, k| h[k] = [] }
  by_local.each_value do |entry|
    type = entry[:label].split('/').first
    results[type] << entry
  end

  write_yaml(results)
  write_markdown(results, cross_listed)
end

def write_yaml(results)
  File.write(File.join(OUTPUT_DIR, 'parity_report.yaml'), results.to_yaml)
end

def write_markdown(results, cross_listed = [])
  out = []
  out << '# Page-by-page parity validation report'
  out << ''
  out << 'Generated against:'
  out << "- deployed reference: `#{DEPLOYED_ROOT}`"
  out << "- new site: `#{LOCAL_ROOT}`"
  out << ''
  out << 'Worst-variant rule: a page passes only when EVERY deployed'
  out << 'variant of it passes ≥95%.'
  out << ''

  # Top-line summary
  total = results.values.flatten.length
  passes = results.values.flatten.count { |r| r[:verdict] == 'pass' }
  warns = results.values.flatten.count { |r| r[:verdict] == 'warn' }
  fails = results.values.flatten.count { |r| r[:verdict] == 'fail' }
  missing = results.values.flatten.count { |r| r[:verdict] == 'missing' }

  out << '## Summary'
  out << ''
  out << "| verdict | count | percent |"
  out << "|---------|-------|---------|"
  out << "| pass (≥95%) | #{passes} | #{(passes.to_f / total * 100).round(1)}% |"
  out << "| warn (80-95%) | #{warns} | #{(warns.to_f / total * 100).round(1)}% |"
  out << "| fail (<80%) | #{fails} | #{(fails.to_f / total * 100).round(1)}% |"
  out << "| missing (no local) | #{missing} | #{(missing.to_f / total * 100).round(1)}% |"
  out << "| **total** | **#{total}** | |"
  out << ''

  # Per-type detail
  results.keys.sort.each do |type|
    arr = results[type]
    next if arr.empty?

    avg = arr.sum { |r| r[:coverage] } / arr.length
    type_pass = arr.count { |r| r[:verdict] == 'pass' }
    out << "## #{type} — #{arr.length} pages, avg #{(avg * 100).round(1)}%, #{type_pass}/#{arr.length} pass"
    out << ''

    # Show failures (top 10 worst)
    worst = arr.select { |r| r[:verdict] != 'pass' }.sort_by { |r| r[:coverage] }.first(10)
    if worst.empty?
      out << '_All pages pass ≥95% parity._'
      out << ''
    else
      out << '### Pages below 95% coverage'
      out << ''
      out << "| page | coverage | variants | missing headings | missing links | missing tables |"
      out << "|------|----------|----------|------------------|---------------|----------------|"
      worst.each do |r|
        out << "| #{r[:label]} | #{(r[:coverage] * 100).round(1)}% | #{r[:variant_count] || 1} | #{r[:missing_headings].length} | #{r[:missing_links_count]} | #{r[:missing_tables].length} |"
      end
      out << ''

      # Specific heading gaps for worst 3
      out << '### Specific heading gaps (worst 3 pages)'
      out << ''
      worst.first(3).each do |r|
        next if r[:missing_headings].empty?

        out << "#### #{r[:human]}"
        out << ''
        out << "Coverage: #{(r[:coverage] * 100).round(1)}% — #{r[:missing_headings].length} missing headings:"
        out << ''
        r[:missing_headings].first(15).each { |h| out << "- #{h.slice(0, 100)}" }
        out << ''
      end
    end
  end

  unless cross_listed.empty?
    out << '## Cross-listed deployed pages (documented anomalies)'
    out << ''
    out << 'These deployed pages embed another register\'s annex content.'
    out << 'The content is rendered on the owning register\'s page; the'
    out << 'variants below are excluded from verdicts to avoid double-'
    out << 'attributing a register\'s data to two pages.'
    out << ''
    out << "| deployed page | coverage if forced | note |"
    out << "|---------------|--------------------|------|"
    cross_listed.each do |r|
      out << "| #{r[:deployed]} | #{(r[:coverage] * 100).round(1)}% | #{r[:cross_listed_note]} |"
    end
    out << ''
  end

  File.write(File.join(OUTPUT_DIR, 'parity_report.md'), out.join("\n"))
  puts "Wrote #{OUTPUT_DIR}/parity_report.md"
  puts "Wrote #{OUTPUT_DIR}/parity_report.yaml"
end

run if __FILE__ == $PROGRAM_NAME
