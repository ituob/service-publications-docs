#!/usr/bin/env ruby
# frozen_string_literal: true

# Add the lib directory to the load path
$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'

# Display help information
def show_help
  puts "Usage: ruby parse_amendments.rb [AMENDMENT_TYPE] [FILE_PATH_PATTERN] [--help | -h]"
  puts
  puts "Description:"
  puts "  Process ITU Operational Bulletin (OB) amendment files of the specified type."
  puts
  puts "Options:"
  puts "  --help, -h            Show this help message"
  puts "  AMENDMENT_TYPE        Type of amendment to parse (default: E118_IIN)"
  puts "  FILE_PATH_PATTERN     Optional file path pattern to process (default: all files of the type)"
  puts
  puts "Supported Amendment Types:"
  Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS.keys.sort.each do |type|
    puts "  #{type}"
  end
  puts
  puts "Examples:"
  puts "  ruby parse_amendments.rb                     # Parse all E118_IIN amendments"
  puts "  ruby parse_amendments.rb E164_ACN            # Parse all E164_ACN amendments"
  puts "  ruby parse_amendments.rb F32_TDI specific.yaml  # Parse a specific F32_TDI amendment file"
  puts
end

# Parse command line arguments
args = ARGV.dup

# Check for help flags first
if args.include?("--help") || args.include?("-h")
  show_help
  exit 0
end

# Default amendment type
amendment_type = "E118_IIN"
file_pattern = nil

# Parse amendment type if provided
if args.size >= 1 && Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS.keys.include?(args[0])
  amendment_type = args.shift
end

# Parse file pattern if provided
file_pattern = args.shift if args.size >= 1

# Get the class for this amendment type
amendment_class = Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS[amendment_type]

if amendment_class.nil?
  puts "Error: Unknown amendment type '#{amendment_type}'"
  puts "Run with --help to see supported amendment types"
  exit 1
end

# Determine the directory for this amendment type
base_dir = File.join(__dir__, '../messages/amendments')
type_dir = File.join(base_dir, amendment_type)

unless Dir.exist?(type_dir)
  puts "Warning: Directory for #{amendment_type} does not exist: #{type_dir}"
  puts "Using base amendments directory instead: #{base_dir}"
  type_dir = base_dir
end

# Get all amendment files of the specified type
amendment_files = if file_pattern
                    if file_pattern.include?('/') || file_pattern.start_with?('../')
                      # Treat as an absolute path if it contains slashes
                      [file_pattern]
                    else
                      # Treat as a filename pattern within the type directory
                      Dir.glob(File.join(type_dir, "*#{file_pattern}*"))
                    end
                  else
                    # Get all YAML files in the type directory
                    Dir.glob(File.join(type_dir, "*.yaml"))
                  end

puts "Found #{amendment_files.size} #{amendment_type} amendment files to process."
puts "=" * 80

# Process each file
amendment_files.each do |file_path|
  puts "Processing #{File.basename(file_path)}..."

  begin
    # Read the YAML file
    yaml_content = File.read(file_path)
    hash = YAML.load(yaml_content)

    # Parse the amendment using the appropriate class
    amendment = amendment_class.parse(hash)

    # Print the parsed content
    puts amendment.to_yaml
    puts "-" * 80
  rescue StandardError => e
    puts "Error processing #{file_path}: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    puts "-" * 80
  end
end

puts "Done!"
