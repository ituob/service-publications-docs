#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "ituob", "lib")
require "ituob"
require "yaml"
require "pp"

# Process all iptn message files
iptn_dir = File.join(File.dirname(__FILE__), "..", "messages", "general", "iptn")

unless Dir.exist?(iptn_dir)
  puts "Error: Directory #{iptn_dir} not found"
  exit 1
end

# Get all YAML files in the iptn directory
iptn_files = Dir.glob(File.join(iptn_dir, "*.yaml"))

puts "Found #{iptn_files.size} iptn message files to process."
puts "=" * 80

# Track files with missing dates
files_with_missing_dates = []

# Process each file
iptn_files.each do |file_path|
  file_name = File.basename(file_path)

  begin
    # Read the YAML file
    yaml_content = YAML.load_file(file_path)

    # Parse the message
    message = Ituob::Models::GeneralIptn.parse(yaml_content)

    # Check if any entry has a missing date
    missing_dates = false
    message.entries.each_with_index do |entry, index|
      if entry.action_date.nil? || entry.action_date.empty?
        missing_dates = true
        puts "#{file_name}: Entry ##{index + 1} (#{entry.applicant} - #{entry.cc_ic}) is missing a date"
      end
    end

    # Add to list of files with missing dates
    files_with_missing_dates << file_name if missing_dates

  rescue StandardError => e
    puts "Error processing #{file_path}: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
  end
end

puts "=" * 80
if files_with_missing_dates.empty?
  puts "All IPTN messages have dates!"
else
  puts "#{files_with_missing_dates.size} files have missing dates:"
  files_with_missing_dates.each do |file|
    puts "- #{file}"
  end
end

puts "Processing complete."
