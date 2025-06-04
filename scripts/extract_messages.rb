#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'fileutils'

# Process YAML file and extract amendments
def extract_amendments_from_file(file_path)
  puts "  Processing file: #{file_path}"
  content = File.read(file_path)

  # Parse using YAML with permissive options (no symbolize_names)
  data = YAML.safe_load(content, permitted_classes: [Date, Time, Symbol])

  # Extract and return amendments
  amendments = []

  if data && data['messages']
    data['messages'].each do |message|
      next unless message['type'] == 'amendment'
      next unless message['target'] && message['target']['publication']

      type = message['target']['publication']
      content = message['contents']['en']

      amendments << {
        'type' => type,
        'message' => content
      }

      puts "  Extracted amendment for publication type: #{type}"
    end
  end

  return amendments
end

# Process YAML file and extract general messages
def extract_general_messages_from_file(file_path)
  puts "  Processing general file: #{file_path}"
  content = File.read(file_path)

  # Fix the YAML content before parsing
  # This is a workaround for the inconsistent indentation in the YAML file
  fixed_content = content.gsub(/^(\s*)-\s+(\w+):/, '\1- \2:')

  # Parse using YAML with permissive options (no symbolize_names)
  data = YAML.safe_load(fixed_content, permitted_classes: [Date, Time, Symbol])

  # Extract and return general messages
  general_messages = []

  if data && data['messages']
    data['messages'].each do |message|
      # Handle messages with no type
      type = message['type'] || 'no_type'

      # Handle the different structures
      if message['contents']
        if message['contents'].is_a?(Hash) && message['contents']['en']
          # Structure 1: Extract contents.en
          content = message['contents']['en']
          general_messages << {
            'type' => type,
            'message' => content
          }
        elsif message['contents'].is_a?(Array)
          # Structure 2: Contents is an array
          general_messages << {
            'type' => type,
            'message' => message
          }
        else
          # Structure 3: Contents is something else
          general_messages << {
            'type' => type,
            'message' => message
          }
        end
      else
        # Structure 4: No contents field
        general_messages << {
          'type' => type,
          'message' => message
        }
      end

      puts "  Extracted general message of type: #{type}"
    end
  end

  return general_messages
end

# Process a single issue directory for amendments
def process_issue(issue_dir)
  issue_number = File.basename(issue_dir)
  yaml_file = File.join(issue_dir, "amendments.yaml")

  return unless File.exist?(yaml_file)
  puts "Processing issue #{issue_number} for amendments..."

  begin
    # Extract amendments directly without full YAML parsing
    amendments = extract_amendments_from_file(yaml_file)

    return if amendments.empty?

    # Group amendments by type
    amendments_by_type = {}

    amendments.each do |amendment|
      type = amendment['type']
      message = amendment['message']

      # Initialize an array for this type if not already done
      amendments_by_type[type] ||= []

      # Add the amendment message to the appropriate type
      amendments_by_type[type] << message
    end

    # Now save each type to its own file
    amendments_by_type.each do |type, messages|
      # Create output directory
      output_dir = File.join("amendments/type", type)
      FileUtils.mkdir_p(output_dir)

      # Handle multiple messages of the same type
      if messages.length == 1
        # Single message - save to issue_number.yaml
        output_file = File.join(output_dir, "#{issue_number}.yaml")
        File.write(output_file, messages.first.to_yaml)
      else
        # Multiple messages - save to issue_number-n.yaml
        messages.each_with_index do |message, index|
          output_file = File.join(output_dir, "#{issue_number}-#{index + 1}.yaml")
          File.write(output_file, message.to_yaml)
        end
      end

      puts "  Extracted #{messages.length} #{type} amendment(s)"
    end
  rescue => e
    puts "  Error processing #{yaml_file}: #{e.message}"
    raise # Re-raise the error to stop execution
  end
end

# Process a single issue directory for general messages
def process_general_issue(issue_dir)
  issue_number = File.basename(issue_dir)
  yaml_file = File.join(issue_dir, "general.yaml")

  return unless File.exist?(yaml_file)
  puts "Processing issue #{issue_number} for general messages..."

  begin
    # Extract general messages
    general_messages = extract_general_messages_from_file(yaml_file)

    return if general_messages.empty?

    # Group general messages by type
    messages_by_type = {}

    general_messages.each do |message|
      type = message['type']
      content = message['message']

      # Initialize an array for this type if not already done
      messages_by_type[type] ||= []

      # Add the message content to the appropriate type
      messages_by_type[type] << content
    end

    # Now save each type to its own file
    messages_by_type.each do |type, messages|
      # Create output directory - use the general/type structure
      output_dir = File.join("general/type", type)
      FileUtils.mkdir_p(output_dir)

      # Handle multiple messages of the same type
      if messages.length == 1
        # Single message - save to issue_number.yaml
        output_file = File.join(output_dir, "#{issue_number}.yaml")
        File.write(output_file, messages.first.to_yaml)
      else
        # Multiple messages - save to issue_number-n.yaml
        messages.each_with_index do |message, index|
          output_file = File.join(output_dir, "#{issue_number}-#{index + 1}.yaml")
          File.write(output_file, message.to_yaml)
        end
      end

      puts "  Extracted #{messages.length} #{type} general message(s)"
    end
  rescue => e
    puts "  Error processing #{yaml_file}: #{e.message}"
    raise # Re-raise the error to stop execution
  end
end

# Main function
def main
  puts "Starting message extraction..."

  # Ensure the base output directories exist
  FileUtils.mkdir_p('messages/amendments')
  FileUtils.mkdir_p('messages/general')
  FileUtils.mkdir_p('messages/general/no_type')  # Create directory for messages with no type

  # Get all issue directories
  issue_dirs = Dir.glob('itu-ob-data/issues/*').select { |d| File.directory?(d) }

  if issue_dirs.empty?
    puts "No issue directories found in 'itu-ob-data/issues/'"
    return
  end

  # Process each issue for amendments and general messages
  issue_dirs.sort_by { |d| File.basename(d).to_i }.each do |issue_dir|
    process_issue(issue_dir)
    process_general_issue(issue_dir)
  end

  puts "Done! Amendments have been extracted to 'messages/amendments' directory."
  puts "General messages have been extracted to 'messages/general' directory."
end

# Run the script
main
