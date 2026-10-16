#!/usr/bin/env ruby
# Script to check IPTN files for content that may not be correctly parsed

require 'yaml'
require 'colorize'

# Directory containing IPTN files
IPTN_DIR = '../messages/general/iptn'

# Action keywords to look for
ACTION_KEYWORDS = [
  'assigned', 'withdrawn', 'reclaimed', 'transferred', 'cancel'
]

# Code patterns to look for
CODE_PATTERNS = [
  '\+881', '\+882', '\+883', 'country code', 'identification code'
]

def check_file(file_path)
  puts "Checking #{file_path}..."

  begin
    # Read the YAML file
    yaml_content = YAML.load_file(file_path)

    # Extract the text content for analysis
    content_text = extract_text(yaml_content)

    # Check for code patterns
    has_codes = CODE_PATTERNS.any? { |pattern| content_text.match(/#{pattern}/i) }

    # Check for action keywords
    has_actions = ACTION_KEYWORDS.any? { |keyword| content_text.match(/#{keyword}/i) }

    # Run parse_amendments.rb for this file
    parse_output = `cd /Users/mulgogi/src/ituob/service-publications-docs/scripts && bundle exec ruby parse_amendments.rb -t general iptn #{File.basename(file_path)} 2>&1`

    # Check if parse_amendments.rb found entries
    has_entries = parse_output.include?('applicant:') ||
                 parse_output.include?('network:') ||
                 parse_output.include?('cc_ic:') ||
                 parse_output.include?('action:')

    # Calculate number of entries from the parse output
    entry_count = parse_output.scan(/applicant:/).count

    # Identify discrepancies
    if has_codes && has_actions && !has_entries
      puts "  WARNING: Contains codes and actions but no entries were parsed!".colorize(:red)
      puts "  Text content contains:".colorize(:yellow)
      puts "    Codes: #{has_codes ? 'YES' : 'NO'}".colorize(has_codes ? :green : :red)
      puts "    Actions: #{has_actions ? 'YES' : 'NO'}".colorize(has_actions ? :green : :red)
      puts "    Parsed entries: #{entry_count}".colorize(entry_count > 0 ? :green : :red)

      # Print a sample of the content
      puts "  Content sample:".colorize(:yellow)
      puts content_text[0..500].gsub(/\n/, ' ')[0..100] + "..."

      return false
    else
      if has_entries
        puts "  OK: #{entry_count} entries parsed".colorize(:green)
      elsif !has_codes && !has_actions
        puts "  OK: No codes or actions found (likely informational only)".colorize(:cyan)
      else
        puts "  WARNING: Content may be missed".colorize(:yellow)
        puts "    Codes: #{has_codes ? 'YES' : 'NO'}".colorize(has_codes ? :green : :red)
        puts "    Actions: #{has_actions ? 'YES' : 'NO'}".colorize(has_actions ? :green : :red)
        puts "    Parsed entries: #{entry_count}".colorize(entry_count > 0 ? :green : :red)
      end
      return true
    end
  rescue => e
    puts "  ERROR: #{e.message}".colorize(:red)
    return false
  end
end

def extract_text(yaml_content)
  text = ""

  # Handle the ProseMirror format
  if yaml_content.is_a?(Hash) && yaml_content['type'] == 'doc' && yaml_content['content']
    text = extract_text_from_content(yaml_content['content'])
  end

  text
end

def extract_text_from_content(content)
  return "" unless content.is_a?(Array)

  result = ""

  content.each do |node|
    if node.is_a?(Hash)
      if node['type'] == 'text' && node['text']
        result += node['text'] + " "
      elsif node['type'] == 'paragraph' && node['content']
        result += extract_text_from_content(node['content']) + "\n"
      elsif node['type'] == 'table' && node['content']
        result += extract_text_from_content(node['content']) + "\n"
      elsif node['type'] == 'table_row' && node['content']
        result += extract_text_from_content(node['content']) + "\n"
      elsif node['type'] == 'table_cell' && node['content']
        result += extract_text_from_content(node['content']) + " "
      elsif node['content']
        result += extract_text_from_content(node['content']) + " "
      end
    end
  end

  result
end

# Main execution
puts "Checking IPTN files for content that may not be correctly parsed..."
puts "======================================================================="

files = Dir.glob(File.join(IPTN_DIR, '*.yaml')).sort
total_files = files.length
problematic_files = []

files.each_with_index do |file_path, index|
  puts "[#{index + 1}/#{total_files}] Checking #{File.basename(file_path)}..."

  unless check_file(file_path)
    problematic_files << file_path
  end

  puts "-----------------------------------------------------------------------"
end

puts "\nSummary:"
puts "======================================================================="
puts "Total files checked: #{total_files}"
puts "Problematic files: #{problematic_files.count}"

if problematic_files.any?
  puts "\nList of problematic files:".colorize(:yellow)
  problematic_files.each do |file|
    puts "  - #{file}"
  end
else
  puts "\nAll files appear to be parsing correctly!".colorize(:green)
end
