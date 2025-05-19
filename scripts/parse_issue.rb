#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'ituob'

# Path to amendment files
ISSUE_DIRS = Dir.glob('../itu-ob-data/issues/*')
# ISSUE_DIRS = [
#  '../itu-ob-data/issues/1000/',
#  '../itu-ob-data/issues/1001/',
# ]

ISSUE_DIRS.each do |issue_dir|
  puts "#" * 80
  puts "Processing #{issue_dir}..."
  issue_data = Ituob::Models::OldIssue.load_issue_dir(issue_dir)
  if issue_data.nil?
    puts "[ERROR] Failed to load issue data from #{issue_dir}"
    next
  end
  puts "%" * 80
  puts issue_data.to_yaml
end

puts "\nDone!"
