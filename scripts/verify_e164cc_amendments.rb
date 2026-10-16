#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "ituob", "lib")
require "ituob"
require "yaml"
require "pp"
require "colorize"

# Directory containing E164_CC files
E164CC_DIR = File.join(File.dirname(__FILE__), "..", "messages", "amendments", "E164_CC")

def process_file(yaml_file)
  puts "Processing #{yaml_file}...".colorize(:cyan)

  full_path = File.join(E164CC_DIR, yaml_file)

  unless File.exist?(full_path)
    puts "Error: File #{full_path} not found".colorize(:red)
    return false
  end

  begin
    yaml_content = YAML.load_file(full_path)

    # Parse the amendment
    amendment = Ituob::Models::E164CCAmendment.parse(yaml_content)

    # Check if the amendment has actions
    if amendment.actions.nil? || amendment.actions.empty?
      puts "Error: No actions found in #{yaml_file}".colorize(:red)
      return false
    end

    # Check if each action has entries
    amendment.actions.each_with_index do |action, i|
      if action.entries.nil? || action.entries.empty?
        puts "Error: Action ##{i + 1} has no entries in #{yaml_file}".colorize(:red)
        return false
      end
    end

    # Display the parsed data
    puts "== Parsed Amendment ==".colorize(:green)
    puts "Amendment Class: #{amendment._class}"
    puts "Position On: #{amendment.position_on}"
    puts "Actions Count: #{amendment.actions.size}"

    # Display each action
    amendment.actions.each_with_index do |action, i|
      puts "\nAction ##{i + 1}:".colorize(:yellow)
      puts "  Type: #{action.action_type}"
      puts "  Position: #{action.position}"

      # Display entries in this action
      action.entries.each_with_index do |entry, j|
        puts "  Entry ##{j + 1}:".colorize(:cyan)
        puts "    Applicant: #{entry.applicant}"
        puts "    Network: #{entry.network}"
        puts "    Country Code and IC: #{entry.cc_ic}"
        puts "    Status: #{entry.status}"
        if entry.formerly
          puts "    Formerly: #{entry.formerly}"
        end
      end
    end

    puts "\nProcessing complete for #{yaml_file}".colorize(:green)
    return true
  rescue Ituob::Models::MissingMandatoryFieldError => e
    puts "Error: #{e.message} in #{yaml_file}".colorize(:red)
    return false
  rescue => e
    puts "Error processing #{yaml_file}: #{e.message}".colorize(:red)
    puts e.backtrace.join("\n").colorize(:red)
    return false
  end
end

# Check if a specific filename was provided
if ARGV.empty?
  puts "Processing all files in #{E164CC_DIR}...".colorize(:cyan)

  # Get all YAML files in the directory
  yaml_files = Dir.glob(File.join(E164CC_DIR, "*.yaml")).map { |f| File.basename(f) }

  if yaml_files.empty?
    puts "No YAML files found in #{E164CC_DIR}".colorize(:red)
    exit 1
  end

  puts "Found #{yaml_files.size} files to process".colorize(:cyan)

  # Process each file
  results = {}
  yaml_files.each do |yaml_file|
    puts "\n" + "="*80
    results[yaml_file] = process_file(yaml_file)
    puts "="*80
  end

  # Print summary
  puts "\n== Summary ==".colorize(:cyan)
  successful = results.count { |_, success| success }
  failed = results.count { |_, success| !success }

  puts "Total files: #{results.size}".colorize(:cyan)
  puts "Successfully processed: #{successful}".colorize(:green)
  puts "Failed to process: #{failed}".colorize(failed > 0 ? :red : :green)

  if failed > 0
    puts "\nFailed files:".colorize(:red)
    results.each do |file, success|
      puts "  - #{file}".colorize(success ? :green : :red) unless success
    end
    exit 1
  else
    puts "\nAll files processed successfully!".colorize(:green)
    exit 0
  end
else
  # Process a single file
  yaml_file = ARGV[0]
  success = process_file(yaml_file)
  exit success ? 0 : 1
end
