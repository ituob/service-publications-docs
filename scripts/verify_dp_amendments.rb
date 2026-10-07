#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "ituob", "lib")
require "ituob"
require "yaml"
require "pp"

# Check if a filename was provided
if ARGV.empty?
  puts "Usage: ruby verify_dp_amendments.rb <yaml_file>"
  exit 1
end

yaml_file = ARGV[0]
full_path = File.join(File.dirname(__FILE__), "..", "messages", "amendments", "DP", yaml_file)

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

# Parse the amendment
amendment = Ituob::Models::DPAmendment.parse(yaml_content)

# Display the parsed data
puts "== Parsed Amendment =="
puts "Amendment Class: #{amendment._class}"
puts "Position On: #{amendment.position_on}"
puts "Actions Count: #{amendment.actions&.size || 0}"

# Display each action
(amendment.actions || []).each_with_index do |action, i|
  puts "\nAction ##{i + 1}:"
  puts "  Type: #{action.action_type}"
  puts "  Position: #{action.position}"

  # Display entries in this action
  action.entries.each_with_index do |entry, j|
    puts "  Entry ##{j + 1}:"
    puts "    Country/Area: #{entry.country_or_area&.en}"
    puts "    Country Code: #{entry.country_code}"
    puts "    International Prefix: #{entry.international_prefix}"
    puts "    National Prefix: #{entry.national_prefix}"
    puts "    National Sig Number: #{entry.national_sig_number}"
    puts "    UTC/DST: #{entry.utc_dst}"
    puts "    Note: #{entry.note&.en}"
  end
end

puts "\nProcessing complete."
