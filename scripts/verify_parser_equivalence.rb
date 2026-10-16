#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Parser output-equivalence verifier.
#
# The amendment parsers are the semantic layer of the site: their
# output feeds both the register snapshots and the issue pages. Any
# change to a parser's output — intentional or accidental — changes
# generated data. This script makes that visible:
#
#   bundle exec ruby scripts/verify_parser_equivalence.rb --capture
#     Parse every registered publication's source amendments and write
#     the serialized result to scripts/output/parser_baseline/{PUB}.json.
#
#   bundle exec ruby scripts/verify_parser_equivalence.rb [--verify]
#     Re-parse and diff against the stored baselines. Exits 1 on any
#     difference so it can gate refactors and parser changes.
#
# Baselines are deterministic (sorted issue keys, stable JSON), so a
# capture diff is reviewable. To intentionally change parser output:
# make the change, re-run --capture, review the baseline diff, commit
# it together with the parser change.

require 'json'
require 'yaml'
require 'fileutils'

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'prosereflect'
require 'ituob/models'
require 'ituob/helpers'
require 'ituob/verifiers/parser_equivalence'

SOURCE_ROOT = File.expand_path('../itu-ob-data/issues', __dir__)
BASELINE_DIR = File.expand_path('output/parser_baseline', __dir__)

# Every {publication_id => parsed-serialization} for the corpus, keyed
# by issue number (sorted for determinism).
def parse_corpus
  registry = Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS
  corpus = Hash.new { |h, k| h[k] = {} }

  Dir.glob(File.join(SOURCE_ROOT, '*', 'amendments.yaml')).sort.each do |path|
    issue = File.basename(File.dirname(path))
    data = YAML.load_file(path, permitted_classes: [Date, Time])
    messages = data.is_a?(Hash) ? data['messages'] : nil
    next unless messages.is_a?(Array)

    messages.each do |msg|
      target = msg.is_a?(Hash) ? msg['target'] : nil
      pub_id = target.is_a?(Hash) ? target['publication'] : nil
      klass = pub_id && registry[pub_id]
      next unless klass
      next if klass == Ituob::Models::TextAmendment # verbatim, no parse

      contents = msg.dig('contents', 'en')
      next unless contents

      begin
        parsed = klass.parse(contents, position_on: target['position_on'], dataset_code: pub_id)
        corpus[pub_id][issue] = Ituob::Verifiers::ParserEquivalence.serialize(parsed)
      rescue StandardError => e
        corpus[pub_id][issue] = { 'error' => "#{e.class}: #{e.message}" }
      end
    end
  end
  corpus
end

def write_baseline(corpus)
  FileUtils.mkdir_p(BASELINE_DIR)
  corpus.keys.sort.each do |pub_id|
    file = File.join(BASELINE_DIR, "#{pub_id}.json")
    File.write(file, JSON.pretty_generate(corpus[pub_id].sort.to_h) + "\n")
  end
  puts "Captured #{corpus.keys.length} publications to #{BASELINE_DIR}"
end

def verify_baseline(corpus)
  failures = 0
  corpus.keys.sort.each do |pub_id|
    file = File.join(BASELINE_DIR, "#{pub_id}.json")
    unless File.file?(file)
      puts "MISSING BASELINE: #{pub_id} (run --capture first)"
      failures += 1
      next
    end

    baseline = JSON.parse(File.read(file))
    current = corpus[pub_id].sort.to_h
    diffs = Ituob::Verifiers::ParserEquivalence.diffs(baseline, current)

    if diffs.empty?
      puts "#{pub_id}: #{current.keys.length} issues OK"
    else
      puts "#{pub_id}: #{diffs.length} DIFFS"
      diffs.first(10).each { |d| puts "  #{d}" }
      failures += diffs.length
    end
  end
  puts "Result: #{failures.zero? ? 'EQUIVALENT' : "#{failures} diffs"}"
  failures.zero?
end

mode = ARGV[0] || '--verify'
corpus = parse_corpus
case mode
when '--capture' then write_baseline(corpus)
when '--verify' then exit(verify_baseline(corpus) ? 0 : 1)
else
  warn "Usage: #{$PROGRAM_NAME} [--capture|--verify]"
  exit 2
end
