#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Run all normalizers in idempotent pipeline order.
#
# Thin wrapper around +Ituob::Normalizers::Pipeline+.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'

source_root = ENV.fetch('ITU_OB_DATA_ROOT',
                        File.expand_path('../itu-ob-data/issues', __dir__))
output_root = ENV.fetch('OB_ISSUES_OUT_PATH',
                        File.expand_path('../ob-issues', __dir__))

issue_repo = Ituob::Repositories::IssueRepository.new(
  source_root: source_root,
  output_root: output_root,
)

pipeline = Ituob::Normalizers::Pipeline.new(issue_repository: issue_repo)
results = pipeline.run

results.each do |r|
  puts "#{r.name}: #{r.files_modified} modified, #{r.files_deleted} deleted, #{r.files_created} created"
  r.details.first(3).each { |d| puts "  #{d}" }
end
