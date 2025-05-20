#!/usr/bin/env ruby
# frozen_string_literal: true

# Add the lib directory to the load path
$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'optparse'

# Display help information
def show_help
  puts "Usage: ruby parse_amendments.rb [--type TYPE] [MESSAGE_TYPE] [FILE_PATH_PATTERN] [--help | -h]"
  puts
  puts "Description:"
  puts "  Process ITU Operational Bulletin (OB) amendment or general message files of the specified type."
  puts
  puts "Options:"
  puts "  --help, -h            Show this help message"
  puts "  --type, -t TYPE       Type of message to parse: 'amendment' or 'general' (default: amendment)"
  puts "  MESSAGE_TYPE          Type of message to parse (default amendment: E118_IIN, default general: running_annexes)"
  puts "  FILE_PATH_PATTERN     Optional file path pattern to process (default: all files of the type)"
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
  puts "Examples:"
  puts "  ruby parse_amendments.rb                           # Parse all E118_IIN amendments"
  puts "  ruby parse_amendments.rb E164_ACN                  # Parse all E164_ACN amendments"
  puts "  ruby parse_amendments.rb F32_TDI specific.yaml     # Parse a specific F32_TDI amendment file"
  puts "  ruby parse_amendments.rb -t general                # Parse all running_annexes general messages"
  puts "  ruby parse_amendments.rb -t general approved_recommendations  # Parse all approved_recommendations general messages"
  puts
end

# Parse command line arguments
args = ARGV.dup
options = {type: 'amendment'}

# Parse options
opt_parser = OptionParser.new do |opts|
  opts.on("-t", "--type TYPE", "Type of message: 'amendment' or 'general'") do |t|
    options[:type] = t
  end

  opts.on("-h", "--help", "Show help") do
    show_help
    exit 0
  end
end

begin
  opt_parser.parse!(args)
rescue OptionParser::InvalidOption => e
  # Check for help flags
  if args.include?("--help") || args.include?("-h")
    show_help
    exit 0
  end
  puts "Error: #{e.message}"
  puts "Run with --help to see valid options"
  exit 1
end

# Set default message types based on message category
message_type = nil
type_to_class_map = nil

case options[:type].downcase
when 'amendment'
  message_type = "E118_IIN"
  type_to_class_map = Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS
when 'general'
  message_type = "running_annexes"
  type_to_class_map = Ituob::Models::OldIssue::GENERAL_TYPE_TO_CLASS
else
  puts "Error: Unknown message category '#{options[:type]}'. Use 'amendment' or 'general'."
  exit 1
end

file_pattern = nil

# Parse message type if provided
if args.size >= 1 && type_to_class_map.keys.include?(args[0])
  message_type = args.shift
end

# Parse file pattern if provided
file_pattern = args.shift if args.size >= 1

# Get the class for this message type
message_class = type_to_class_map[message_type]

if message_class.nil?
  puts "Error: Unknown #{options[:type]} type '#{message_type}'"
  puts "Run with --help to see supported types"
  exit 1
end

# Determine the directory for this message type
base_dir = File.join(__dir__, "../messages/#{options[:type] == 'amendment' ? 'amendments' : 'general'}")
type_dir = File.join(base_dir, message_type)

unless Dir.exist?(type_dir)
  puts "Warning: Directory for #{message_type} does not exist: #{type_dir}"
  puts "Using base #{options[:type]}s directory instead: #{base_dir}"
  type_dir = base_dir
end

# Get all message files of the specified type
message_files = if file_pattern
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

puts "Found #{message_files.size} #{message_type} #{options[:type]} files to process."
puts "=" * 80

# Process each file
message_files.each do |file_path|
  puts "Processing #{File.basename(file_path)}..."

  begin
    # Read the YAML file
    yaml_content = File.read(file_path)
    hash = YAML.load(yaml_content)

    # Parse the message using the appropriate class
    message = message_class.parse(hash)

    # Print the parsed content
    puts message.to_yaml
    puts "-" * 80
  rescue StandardError => e
    puts "Error processing #{file_path}: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    puts "-" * 80
  end
end

puts "Done!"
