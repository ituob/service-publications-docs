#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "ituob", "lib")
require "ituob"
require "yaml"
require "pp"

# Check if a filename was provided
if ARGV.empty?
  puts "Usage: ruby verify_ipns_messages.rb <yaml_file>"
  exit 1
end

yaml_file = ARGV[0]
full_path = File.join(File.dirname(__FILE__), "..", "messages", "general", "ipns", yaml_file)

unless File.exist?(full_path)
  puts "Error: File #{full_path} not found"
  exit 1
end

puts "Processing #{yaml_file}..."
yaml_content = YAML.load_file(full_path)

# Print the raw YAML structure
puts "\n== YAML Structure =="
pp yaml_content
puts

# Print document content if it exists
if yaml_content && yaml_content["content"]
  puts "== Document Content Overview =="
  yaml_content["content"].each_with_index do |item, index|
    type = item["type"]
    case type
    when "paragraph"
      text = item.dig("content", 0, "text") || ""
      puts "Paragraph #{index}: #{text.strip[0..60]}#{"..." if text.length > 60}"
    when "table"
      puts "Table #{index}: #{item["content"].size} rows"
      # Print first row as sample
      if item["content"].first && item["content"].first["content"]
        cells = item["content"].first["content"]
        cell_texts = cells.map do |cell|
          cell_content = cell.dig("content", 0, "content", 0, "text") || ""
          cell_content.strip[0..20]
        end
        puts "  Sample row: #{cell_texts.join(' | ')}"
      end
    end
  end
  puts
end

# Parse the message
message = Ituob::Models::GeneralIpns.parse(yaml_content)

# Display the parsed data
puts "== Parsed Message =="
puts "Message Class: #{message.class}"
puts "Type: #{message.type}"
puts "Network: #{message.network}"
puts "MCC/MNC: #{message.mcc_mnc}"
puts "Date of Assignment: #{message.date_of_assignment}"
puts "Notes: #{message.notes}"

puts "\nProcessing complete."
