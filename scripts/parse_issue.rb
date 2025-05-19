#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'ituob'

# Get filter type from command line args
filter_type = ARGV[0]

# Path to amendment files
ISSUE_DIRS = Dir.glob('../itu-ob-data/issues/*')
# ISSUE_DIRS = [
#  '../itu-ob-data/issues/1000/',
#  '../itu-ob-data/issues/1001/',
# ]

if filter_type
  puts "Filtering results for type: #{filter_type}"
end

ISSUE_DIRS.each do |issue_dir|
  puts "#" * 80
  puts "Processing #{issue_dir}..."
  issue_data = Ituob::Models::OldIssue.load_issue_dir(issue_dir)
  if issue_data.nil?
    puts "[ERROR] Failed to load issue data from #{issue_dir}"
    next
  end

  if filter_type
    # Check if filter_type is an amendment type
    if Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS.keys.include?(filter_type)
      # Get the class for this amendment type
      amendment_class = Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS[filter_type]

      # Filter amendments by class
      filtered_amendments = issue_data.amendments&.select { |a| a.is_a?(amendment_class) }

      if filtered_amendments&.any?
        puts "%" * 80
        puts filtered_amendments.to_yaml
      else
        puts "[INFO] No amendments of type '#{filter_type}' found in #{issue_dir}"
      end
    # Check if filter_type is a general message type
    elsif Ituob::Models::OldIssue::GENERAL_TYPE_TO_CLASS.keys.include?(filter_type)
      if issue_data.general_messages&.any? { |g| g.type == filter_type }
        puts "%" * 80
        filtered_general = issue_data.general_messages.select { |g| g.type == filter_type }
        puts filtered_general.to_yaml
      else
        puts "[INFO] No general messages of type '#{filter_type}' found in #{issue_dir}"
      end
    else
      puts "[WARNING] Unknown filter type: #{filter_type}. Showing all data."
      puts "%" * 80
      puts issue_data.to_yaml
    end
  else
    # No filter specified, show all data
    puts "%" * 80
    puts issue_data.to_yaml
  end
end

puts "\nDone!"
