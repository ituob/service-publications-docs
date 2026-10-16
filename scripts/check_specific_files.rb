#!/usr/bin/env ruby

require "yaml"
$LOAD_PATH.unshift(File.expand_path("../ituob/lib", __dir__))
require "ituob"

problem_files = [
  "../messages/general/iptn/1155.yaml",
  "../messages/general/iptn/1175.yaml",
  "../messages/general/iptn/1190.yaml",
  "../messages/general/iptn/1232.yaml",
  "../messages/general/iptn/986.yaml"
]

puts "Checking specific problematic IPTN files..."
puts "==========================================================="

problem_files.each do |file|
  puts "Checking #{File.basename(file)}..."
  begin
    yaml_data = YAML.load_file(file)
    msg = Ituob::Models::GeneralIptn.parse(yaml_data)

    if msg.entries.empty?
      puts "  WARNING: No entries parsed from this file"
    else
      puts "  OK: #{msg.entries.count} entries parsed"
      msg.entries.each_with_index do |entry, i|
        puts "    [#{i+1}] Applicant: #{entry.applicant}"
        puts "        CC/IC: #{entry.cc_ic}"
        puts "        Action: #{entry.action}"
        puts "        Date: #{entry.action_date}"
        puts "        Network: #{entry.network}" if entry.network
        puts ""
      end
    end
  rescue => e
    puts "  ERROR: #{e.message}"
  end
  puts "-----------------------------------------------------------"
end
