#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'ituob'

# Check if DEBUG mode is enabled
DEBUG = ENV['DEBUG'] == 'true'

# Display help information
def show_help
  puts "Usage: ruby parse_issue.rb [FILTER_TYPE] [ISSUE_SELECTOR] [--help | -h]"
  puts
  puts "Description:"
  puts "  Process ITU Operational Bulletin (OB) issue data and optionally filter by amendment or general message type."
  puts
  puts "Options:"
  puts "  --help, -h       Show this help message"
  puts "  FILTER_TYPE      Filter results by amendment type or general message type"
  puts "  ISSUE_SELECTOR   Select specific issues to process:"
  puts "                   - Single issue: '1000'"
  puts "                   - Range of issues: '1000-1050'"
  puts "                   - List of issues: '1000,1050,1100'"
  puts
  puts "Examples:"
  puts "  ruby parse_issue.rb E164_ACN              # Filter by E164_ACN for all issues"
  puts "  ruby parse_issue.rb E164_ACN 1000         # Filter by E164_ACN for issue 1000"
  puts "  ruby parse_issue.rb E164_ACN 1000-1050    # Filter by E164_ACN for issues 1000-1050"
  puts "  ruby parse_issue.rb E164_ACN 1000,1050    # Filter by E164_ACN for issues 1000 and 1050"
  puts "  ruby parse_issue.rb 1000                  # Process only issue 1000 (no filter)"
  puts
  puts "Supported Amendment Types:"
  Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS.keys.sort.each do |type|
    puts "  #{type}"
  end
  puts
  puts "Supported General Message Types:"
  Ituob::Models::OldIssue::GENERAL_TYPE_TO_CLASS.keys.sort.each do |type|
    puts "  #{type}"
  end
  puts
end

# Parse command line arguments
args = ARGV.dup
filter_type = nil
issue_selector = nil

# Check for help flags first
if args.include?("--help") || args.include?("-h")
  show_help
  exit 0
end

# Parse arguments
if args.size >= 1
  # Check if first arg is a filter type
  if Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS.keys.include?(args[0]) ||
     Ituob::Models::OldIssue::GENERAL_TYPE_TO_CLASS.keys.include?(args[0])
    filter_type = args.shift
    issue_selector = args.shift if args.size >= 1
  else
    # First arg must be an issue selector
    issue_selector = args.shift
  end
end

# Get all issue directories
all_issue_dirs = Dir.glob('../itu-ob-data/issues/*')

# Filter issue directories based on issue_selector if provided
if issue_selector
  # Extract issue numbers from directory paths
  issue_numbers = all_issue_dirs.map do |dir|
    dir.split('/').last.to_i
  end

  # Parse issue selector
  selected_issue_numbers = []

  if issue_selector.include?('-')
    # Range of issues
    start_issue, end_issue = issue_selector.split('-').map(&:to_i)
    selected_issue_numbers = (start_issue..end_issue).to_a
  elsif issue_selector.include?(',')
    # List of issues
    selected_issue_numbers = issue_selector.split(',').map(&:to_i)
  else
    # Single issue
    selected_issue_numbers = [issue_selector.to_i]
  end

  # Filter directories to only include selected issues
  ISSUE_DIRS = all_issue_dirs.select do |dir|
    issue_number = dir.split('/').last.to_i
    selected_issue_numbers.include?(issue_number)
  end
else
  ISSUE_DIRS = all_issue_dirs
end

# Initialize counters
total_issues = 0
issues_with_target_amendments = 0

if filter_type
  puts "Filtering results for type: #{filter_type}"
end

ISSUE_DIRS.each do |issue_dir|
  total_issues += 1
  issue_number = issue_dir.split('/').last

  puts "#" * 80 if DEBUG
  puts "Processing #{issue_dir}..." if DEBUG

  issue_data = Ituob::Models::OldIssue.load_issue_dir(issue_dir)
  if issue_data.nil?
    puts "[ERROR] Failed to load issue data from #{issue_dir}"
    next
  end

  unless filter_type
    # No filter specified, show all data
    puts "%" * 80
    puts "Issue #{issue_number}:"
    puts issue_data.to_yaml
    next
  end

  # Check if filter_type is an amendment type
  if Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS.keys.include?(filter_type)
    # Get the class for this amendment type
    amendment_class = Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS[filter_type]

    # Filter amendments by class
    filtered_amendments = issue_data.amendments&.select { |a| a.is_a?(amendment_class) }

    if filtered_amendments&.any?
      issues_with_target_amendments += 1
      puts "%" * 80
      puts "Issue #{issue_number}:"
      filtered_amendments.each do |amendment|
        puts amendment.to_yaml
      end
    elsif DEBUG
      puts "[INFO] No amendments of type '#{filter_type}' found in #{issue_dir}"
    end

  # Check if filter_type is a general message type
  elsif Ituob::Models::OldIssue::GENERAL_TYPE_TO_CLASS.keys.include?(filter_type)
    general_class = Ituob::Models::OldIssue::GENERAL_TYPE_TO_CLASS[filter_type]
    filtered_general = issue_data.general_messages&.select { |g| g.is_a?(general_class) }

    if filtered_general&.any?
      puts "%" * 80
      puts "Issue #{issue_number}:"
      filtered_general.each do |general|
        puts general.to_yaml
      end
    elsif DEBUG
      puts "[INFO] No general messages of type '#{filter_type}' found in #{issue_dir}"
    end

  else
    puts "[WARNING] Unknown filter type: #{filter_type}. Showing all data."
    puts "%" * 80
    puts issue_data.to_yaml
  end
end

# Display summary if a filter was specified
if filter_type && Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS.keys.include?(filter_type)
  puts "\n#" + "=" * 78 + "#"
  puts "Summary: Found #{issues_with_target_amendments} issues with #{filter_type} amendments out of #{total_issues} total issues processed."
  puts "#" + "=" * 78 + "#"
end

puts "\nDone!"
