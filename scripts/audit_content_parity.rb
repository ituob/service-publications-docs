#!/usr/bin/env ruby
# frozen_string_literal: true
# Compare visible text content between deployed www.ituob.org (Jekyll
# _site) and the new Astro dist/ build for sampled issues. Reports
# coverage per issue.
#
# ROLE: early single-page sampling tool. The parity GATE is
# scripts/parity_report.rb (worst-variant rule + cross-listed
# anomalies) — take verdicts from there, not from this script. This
# one remains useful for quick single-page comparisons while debugging.

require 'fileutils'
require 'set'
require 'yaml'

DEPLOYED_ROOT = ENV.fetch('DEPLOYED_SITE',
                          File.expand_path('../../ituob.org/_site', __dir__))
LOCAL_ROOT = ENV.fetch('LOCAL_DIST',
                       File.expand_path('../../ituob.org-v2/dist', __dir__))

SAMPLES = (
  if ARGV.any?
    ARGV.flat_map { |a| a.include?('-') ? Range.new(*a.split('-').map(&:to_i)).to_a : [a.to_i] }
  else
    [955, 970, 1000, 1020, 1050, 1080, 1100, 1130, 1150, 1180, 1200, 1230]
  end
).freeze
THRESHOLD = 0.95

OUTPUT_PATH = ENV.fetch('OUTPUT_PATH',
                        File.expand_path('../scripts/output/content-parity.yaml', __dir__))

def strip_html(html)
  text = html.dup
  text = text.gsub(/<style[^>]*>.*?<\/style>/m, '')
  text = text.gsub(/<script[^>]*>.*?<\/script>/m, '')
  text = text.gsub(/<[^>]+>/, ' ')
  text = text.gsub(/&nbsp;/, ' ')
  text = text.gsub(/&amp;/, '&')
  text = text.gsub(/&lt;/, '<')
  text = text.gsub(/&gt;/, '>')
  text = text.gsub(/&quot;/, '"')
  text = text.gsub(/&#39;/, "'")
  text = text.gsub(/&#\d+;/, ' ')
  # OB canonical date format uses Roman numerals (15.V.2016). Both deployed
  # and new site render in this format; do NOT normalize.
  text = text.gsub(/\s+/, ' ').strip
  text
end

STOP_WORDS = %w[
  the and for with that this from into when have has had not are was were been
  also one two three four five six more most such other over both up out off via
  its his her their our your its them they them then there here these those
  while whom whose what when where why how can may will could would should might
  must shall
].freeze

CONTENT_WORDS = %w[
  itu itu-t ob publication date issue amendment bureau standardization
  radiocommunication tsb br recommendation country mobile network carrier
  code codes signall signalling assigned identifier prefix dialling telephone
  numbering address service restriction callback annex annexed position
  approval approved list lists operational bulletin
].to_set.freeze

def tokens_for(path)
  return [] unless File.file?(path)
  strip_html(File.read(path, encoding: 'utf-8'))
       .scan(/\p{Word}+/).map(&:downcase).reject { |w| w.length < 3 }
       .reject { |w| STOP_WORDS.include?(w) }
end

def frequency_weighted_coverage(deployed_words, local_words)
  return 1.0 if deployed_words.empty?
  d_freq = deployed_words.tally
  l_freq = local_words.tally
  matched = 0
  total = 0
  d_freq.each do |word, count|
    weight = [count, 5].min   # cap per-word weight so a single spam word doesn't dominate
    total += weight
    matched += [weight, l_freq[word] || 0].min
  end
  matched.to_f / total
end

results = []
all_ok = true
SAMPLES.each do |issue|
  deployed_path = File.join(DEPLOYED_ROOT, 'issues', "#{issue}-en", 'index.html')
  local_path = File.join(LOCAL_ROOT, 'issues', issue.to_s, 'index.html')

  deployed_words = tokens_for(deployed_path)
  local_words = tokens_for(local_path)

  next if deployed_words.empty? && local_words.empty?

  intersection = deployed_words.uniq & local_words.uniq
  coverage = frequency_weighted_coverage(deployed_words, local_words)
  exact_coverage = if deployed_words.uniq.empty?
                     local_words.uniq.empty? ? 1.0 : 0.0
                   else
                     intersection.length.to_f / deployed_words.uniq.length
                   end

  results << {
    issue: issue,
    deployed_words: deployed_words.length,
    local_words: local_words.length,
    coverage: coverage.round(4),
    exact_coverage: exact_coverage.round(4),
  }
  all_ok = false if coverage < THRESHOLD
end

FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
File.write(OUTPUT_PATH, results.to_yaml)

if results.any?
  avg = results.sum { |r| r[:coverage] } / results.length.to_f
  puts "Content parity (frequency-weighted): avg #{format('%.1f%%', avg * 100)} (#{results.length} samples)"
  results.each do |r|
    pct = format('%.1f%%', r[:coverage] * 100)
    flag = r[:coverage] < THRESHOLD ? ' (under threshold)' : ''
    puts "  OB #{r[:issue]}: deployed=#{r[:deployed_words]} local=#{r[:local_words]} weighted=#{pct}#{flag}"
  end
end

exit(all_ok ? 0 : 1)
