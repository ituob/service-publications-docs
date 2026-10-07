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

# Process each file
iptn_files.each do |file_path|
  file_name = File.basename(file_path)
  puts "Processing #{file_name}..."

  begin
    # Read the YAML file
    yaml_content = YAML.load_file(file_path)

    # Parse the message
    message = Ituob::Models::GeneralIptn.parse(yaml_content)

    # Display the parsed data
    puts "Message Class: #{message.class}"
    puts "Type: #{message.type}"
    puts "Number of Entries: #{message.entries.size}"

    # Display each entry
    message.entries.each_with_index do |entry, index|
      puts "Entry ##{index + 1}:"
      puts "  Applicant: #{entry.applicant}"
      puts "  Network: #{entry.network}"
      puts "  Country Code and Identification Code: #{entry.cc_ic}"
      puts "  Action: #{entry.action}"
      puts "  Action Date: #{entry.action_date}"
      puts "  Formerly: #{entry.formerly}" if entry.formerly
    end

    # Display notes if present
    if message.notes && !message.notes.empty?
      puts "Notes: #{message.notes[0..100]}..." if message.notes.length > 100
      puts "Notes: #{message.notes}" if message.notes.length <= 100
    end

    puts "-" * 80
  rescue StandardError => e
    puts "Error processing #{file_path}: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    puts "-" * 80
  end
end

puts "Processing complete."
