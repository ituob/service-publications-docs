#!/usr/bin/env ruby

require "yaml"
require "fileutils"
$LOAD_PATH.unshift(File.expand_path("../ituob/lib", __dir__))
require "ituob"

# This script generates a template YAML file for manual editing
# when automatic parsing is insufficient

def generate_template(source_file, target_dir = "../messages/general/iptn/manual")
  # Ensure target directory exists
  FileUtils.mkdir_p(target_dir)

  # Get the base filename
  basename = File.basename(source_file)
  target_file = File.join(target_dir, basename)

  # Load the original YAML content for reference
  begin
    yaml_data = YAML.load_file(source_file)

    # Create a minimal template
    template = {
      "type" => "iptn",
      "entries" => [
        {
          "applicant" => "",
          "network" => "",
          "cc_ic" => "",
          "action" => "", # assigned, withdrawn, reclaimed, etc.
          "action_date" => "",
          "formerly" => "",
          "notes" => ""
        }
      ],
      "notes" => ""
    }

    # Save the template
    File.open(target_file, "w") do |f|
      f.write(YAML.dump(template))
    end

    puts "Created template at #{target_file}"
    puts "Please fill in the details manually based on the content in #{source_file}"

    # Try to print some helpful content from the original file
    if yaml_data && yaml_data["content"]
      puts "\nContent preview from original file:"
      yaml_data["content"].each do |node|
        if node["type"] == "paragraph" && node["content"]
          node["content"].each do |content_node|
            if content_node["type"] == "text"
              puts "- #{content_node['text'].strip}"
            end
          end
        end
      end
    end

  rescue => e
    puts "Error processing #{source_file}: #{e.message}"
  end
end

if ARGV.empty?
  problem_files = [
    "../messages/general/iptn/1155.yaml",
    "../messages/general/iptn/1175.yaml",
    "../messages/general/iptn/1190.yaml",
    "../messages/general/iptn/1232.yaml",
    "../messages/general/iptn/986.yaml"
  ]

  problem_files.each do |file|
    generate_template(file)
  end
else
  ARGV.each do |file|
    generate_template(file)
  end
end

puts "\nAfter filling in the templates, add the following code to parse_amendments.rb:"
puts "===================================================================="
puts "# Handle manual IPTN files"
puts "manual_file = File.join('messages', 'general', 'iptn', 'manual', File.basename(filename))"
puts "if File.exist?(manual_file)"
puts "  puts \"Using manually curated file: \#{manual_file}\""
puts "  yaml_data = YAML.load_file(manual_file)"
puts "  result = yaml_data # Already in correct format"
puts "else"
puts "  # Regular parsing logic..."
puts "end"
puts "===================================================================="
