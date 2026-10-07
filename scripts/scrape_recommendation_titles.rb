#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Scrape every recommendation title from the deployed Jekyll _site and
# persist them as YAML metadata under itu-ob-data/recommendations/{code}/.
#
# The deployed site uses the +relaton+ gem to fetch titles from the ITU
# bibliography database at build time. We mirror the result as static
# YAML so the new Astro build doesn't need network access or relaton.

require 'fileutils'
require 'nokogiri'
require 'yaml'

DEPLOYED_ROOT = File.expand_path('../../ituob.org/_site', __dir__)
TARGET_ROOT = File.expand_path('../../itu-ob-data/recommendations', __dir__)

# Pattern: <li>ITU-T {code} ({version}): {title}</li>
# The code may contain spaces, slashes, parentheses, "Amd N", "Cor N".
LI_PATTERN = %r{
  <li>\s*
  ITU-T\s+([^<(]+?)\s*        # code (lazy, up to " (" or "<")
  (?:\(([^)]+)\)\s*:)?\s*     # optional (version):
  ([^<\n][^<\n]*?)\s*          # title (non-greedy, no "<")
  \s*</li>
}x

titles = Hash.new { |h, k| h[k] = {} }
count = 0
Dir.glob(File.join(DEPLOYED_ROOT, 'issues', '*-en', 'index.html')).sort.each do |path|
  html = File.read(path, encoding: 'utf-8')
  html.scan(LI_PATTERN) do |code, version, title|
    next if code.nil? || title.nil?

    code = code.strip
    title = title.strip
    next if code.empty? || title.empty?
    next if title.match?(/\A[\s\W]*\z/) # only punctuation

    titles[code]['en'] = title
    count += 1
  end
end

puts "Discovered #{count} (code, title) pairs; #{titles.length} unique codes."

written = 0
titles.each do |code, title_hash|
  dir = File.join(TARGET_ROOT, code)
  FileUtils.mkdir_p(dir)
  meta_path = File.join(dir, 'meta.yaml')

  existing = File.exist?(meta_path) ? (YAML.safe_load(File.read(meta_path)) || {}) : {}
  existing['code'] = code
  existing_title = existing['title'] || {}
  existing_title['en'] ||= title_hash['en']
  existing['title'] = existing_title

  File.write(meta_path, existing.to_yaml.gsub(/\A---\n/, ''))
  written += 1
end

puts "Wrote #{written} recommendation metadata files to #{TARGET_ROOT}."
