#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Link-level parity validator: for every internal <a href="..."> on
# the deployed site, check whether the new Astro site has an
# equivalent (after URL mapping). Reports missing-link gaps per page.
#
# URL mapping logic lives in Ituob::Parity::UrlMap (lib) so the spec
# can exercise it without running the full audit.

require 'pathname'
require 'fileutils'
require 'json'
require 'yaml'
require 'nokogiri'

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob/parity'

DEPLOYED_ROOT = ENV.fetch('DEPLOYED_SITE',
                          File.expand_path('../../.parity-reference/jekyll/_site', __dir__))
LOCAL_ROOT    = ENV.fetch('LOCAL_DIST',
                          File.expand_path('../../ituob.org-v2/dist', __dir__))
OUTPUT_DIR    = ENV.fetch('OUTPUT_DIR',
                          File.expand_path('output/link_parity', __dir__))

def local_file_exists?(url, local_root)
  return true if url.nil?

  path_part = url.split('#', 2).first
  path = if path_part.end_with?('/')
           File.join(local_root, path_part, 'index.html')
         else
           File.join(local_root, path_part)
         end
  File.file?(path)
end

def extract_links(html)
  doc = Nokogiri::HTML(html)
  doc.css('a').map { |a| a['href'] }.compact.uniq
end

def audit_page(deployed_html, local_root)
  links = extract_links(deployed_html)
  flagged = []

  links.each do |href|
    mapped = Ituob::Parity::UrlMap.map(href)
    next if mapped.nil?

    page_url = mapped.sub(/#.*\z/, '')
    unless local_file_exists?(page_url, local_root)
      flagged << { deployed: href, mapped: mapped }
    end
  end

  { total_links: links.length, flagged: flagged }
end

def collect_pages(root)
  pages = []
  Pathname.new(root).find do |path|
    next unless path.file?
    next unless path.to_s.end_with?('.html')
    next unless path.to_s.include?('/index.html')

    pages << path.relative_path_from(root).to_s
  end
  pages
end

def run
  FileUtils.mkdir_p(OUTPUT_DIR)

  deployed_pages = collect_pages(DEPLOYED_ROOT)
  puts "Auditing links on #{deployed_pages.length} deployed pages..."

  results = []
  deployed_pages.each_with_index do |rel, idx|
    deployed_path = File.join(DEPLOYED_ROOT, rel)
    deployed_html = File.read(deployed_path, encoding: 'utf-8')
    label = rel.sub(/\/index\.html\z/, '/').sub(/index\.html\z/, '')
    page_result = audit_page(deployed_html, LOCAL_ROOT)
    page_result[:label] = label
    results << page_result

    puts "  #{idx + 1}/#{deployed_pages.length}..." if (idx + 1) % 50 == 0
  end

  File.write(File.join(OUTPUT_DIR, 'link_report.yaml'), results.to_yaml)

  total_flagged = results.sum { |r| r[:flagged].length }
  total_links = results.sum { |r| r[:total_links] }
  puts ""
  puts "Total links: #{total_links}"
  puts "Flagged (no Astro equivalent): #{total_flagged}"

  if total_flagged > 0
    puts ""
    puts "Top 10 most-flagged pages:"
    results.sort_by { |r| -r[:flagged].length }.first(10).each do |r|
      next if r[:flagged].empty?

      puts "  #{r[:label]}: #{r[:flagged].length} of #{r[:total_links]} links"
    end

    puts ""
    puts "Most common flagged link patterns:"
    patterns = Hash.new(0)
    results.each do |r|
      r[:flagged].each do |f|
        pattern = f[:deployed].strip.gsub(/\d+/, 'N').gsub(%r{/issues/N/.*}, '/issues/N/...')
        patterns[pattern] += 1
      end
    end
    patterns.sort_by { |_, c| -c }.first(10).each do |p, c|
      puts "  #{c}x #{p.inspect}"
    end
  end

  puts ""
  puts "Report: #{OUTPUT_DIR}/link_report.yaml"
end

run if __FILE__ == $PROGRAM_NAME
