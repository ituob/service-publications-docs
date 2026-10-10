#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "ituob", "lib")
require "ituob"
require "yaml"
require "pp"

# Process all ipns message files
ipns_dir = File.join(File.dirname(__FILE__), "..", "messages", "general", "ipns")

unless Dir.exist?(ipns_dir)
  puts "Error: Directory #{ipns_dir} not found"
  exit 1
end

# Get all YAML files in the ipns directory
ipns_files = Dir.glob(File.join(ipns_dir, "*.yaml"))

puts "Found #{ipns_files.size} ipns message files to process."
puts "=" * 80

# Process each file
ipns_files.each do |file_path|
  file_name = File.basename(file_path)
  puts "Processing #{file_name}..."

  begin
    # Read the YAML file
    yaml_content = YAML.load_file(file_path)

    # Parse the message
    message = Ituob::Models::GeneralIpns.parse(yaml_content)

    # Display the parsed data
    puts "Message Class: #{message.class}"
    puts "Type: #{message.type}"
    puts "Network: #{message.network}"
    puts "MCC/MNC: #{message.mcc_mnc}"
    puts "Date of Assignment: #{message.date_of_assignment}"
    puts "Notes: #{message.notes[0..100]}..." if message.notes && message.notes.length > 100
    puts "Notes: #{message.notes}" if message.notes && message.notes.length <= 100

    puts "-" * 80
  rescue StandardError => e
    puts "Error processing #{file_path}: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    puts "-" * 80
  end
end

puts "Processing complete."
