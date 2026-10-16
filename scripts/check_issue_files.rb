#!/usr/bin/env ruby
# Script to check that all itu-ob-data/issues/* directories have the required YAML files

require 'colorize'
require 'optparse'
require 'csv'

ISSUES_DIR = File.expand_path('../itu-ob-data/issues', __dir__)
REQUIRED_FILES = %w[general.yaml meta.yaml amendments.yaml]

# Parse command line options
options = {
  verbose: false,
  csv: nil,
  json: nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($0)} [options]"

  opts.on("-v", "--verbose", "Show more detailed information") do
    options[:verbose] = true
  end

  opts.on("--csv FILE", "Export results to CSV file") do |file|
    options[:csv] = file
  end

  opts.on("--json FILE", "Export results to JSON file") do |file|
    options[:json] = file
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

puts "Checking issues directories for required YAML files...".bold

# Track statistics
stats = {
  total_dirs: 0,
  compliant_dirs: 0,
  non_compliant_dirs: 0,
  missing_files: Hash.new(0)
}

# Results for reporting
results = []

# Get all issue directories
issue_dirs = Dir.glob(File.join(ISSUES_DIR, '*')).select { |f| File.directory?(f) }
stats[:total_dirs] = issue_dirs.size

puts "Found #{stats[:total_dirs]} issue directories"
puts

# Check each directory for required files
issue_dirs.sort_by { |dir| dir.split('/').last.to_i }.each do |issue_dir|
  issue_number = File.basename(issue_dir)
  missing_files = []

  REQUIRED_FILES.each do |required_file|
    file_path = File.join(issue_dir, required_file)
    missing_files << required_file unless File.exist?(file_path)
  end

  if missing_files.empty?
    stats[:compliant_dirs] += 1
    puts "Issue #{issue_number}: ✓".green if options[:verbose]
  else
    stats[:non_compliant_dirs] += 1
    missing_files.each { |file| stats[:missing_files][file] += 1 }

    puts "Issue #{issue_number}:".red
    missing_files.each do |file|
      puts "  Missing: #{file}".red
    end

    # Store results for reporting
    results << {
      issue: issue_number,
      missing_files: missing_files
    }
  end
end

puts "\nSummary:".bold
puts "Total issue directories: #{stats[:total_dirs]}"
puts "Compliant directories: #{stats[:compliant_dirs]} (#{(stats[:compliant_dirs].to_f / stats[:total_dirs] * 100).round(2)}%)"
puts "Non-compliant directories: #{stats[:non_compliant_dirs]} (#{(stats[:non_compliant_dirs].to_f / stats[:total_dirs] * 100).round(2)}%)"

if stats[:non_compliant_dirs] > 0
  puts "\nMissing files breakdown:".bold
  stats[:missing_files].sort_by { |_, count| -count }.each do |file, count|
    puts "  #{file}: #{count} directories"
  end

  puts "\nNon-compliant issues:".bold
  results.each do |result|
    puts "  Issue #{result[:issue]}: missing #{result[:missing_files].join(', ')}"
  end
end

# Export to CSV if requested
if options[:csv]
  CSV.open(options[:csv], "wb") do |csv|
    csv << ["Issue", "Missing Files"]
    results.each do |result|
      csv << [result[:issue], result[:missing_files].join(", ")]
    end
  end
  puts "\nResults exported to CSV: #{options[:csv]}".green
end

# Export to JSON if requested
if options[:json]
  require 'json'
  File.write(options[:json], JSON.pretty_generate(results))
  puts "\nResults exported to JSON: #{options[:json]}".green
end

puts "\nUsage:".bold
puts "  #{File.basename($0)}         # Check for missing files"
puts "  #{File.basename($0)} --verbose # Show detailed information for all issues"
puts "  #{File.basename($0)} --csv report.csv # Export results to CSV"
puts "  #{File.basename($0)} --json report.json # Export results to JSON"
