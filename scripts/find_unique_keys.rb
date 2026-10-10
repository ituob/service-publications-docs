#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'set'
require 'find'

# Class to analyze a dataset and find unique keys
class DatasetAnalyzer
  attr_reader :dataset_path, :dataset_code, :schema, :data, :required_keys

  def initialize(dataset_path)
    @dataset_path = dataset_path
    @dataset_code = File.basename(dataset_path)
    load_schema
    load_data
  end

  def load_schema
    schema_path = File.join(@dataset_path, 'schema-data.yaml')
    unless File.exist?(schema_path)
      puts "Warning: No schema-data.yaml found for #{@dataset_code}"
      @required_keys = []
      return
    end

    @schema = YAML.load_file(schema_path, aliases: true)
    @required_keys = @schema.dig('items', 'required') || []
  end

  def load_data
    data_path = File.join(@dataset_path, 'data.yaml')

    # If data.yaml doesn't exist, try looking in data/ directory
    unless File.exist?(data_path)
      data_dir = File.join(@dataset_path, 'data')
      if File.directory?(data_dir)
        # Combine all YAML files in the data/ directory
        @data = []
        Dir.glob(File.join(data_dir, '*.yaml')).each do |file|
          yaml_content = YAML.load_file(file, aliases: true)
          if yaml_content.is_a?(Array)
            @data.concat(yaml_content)
          elsif yaml_content.is_a?(Hash)
            @data << yaml_content
          end
        end
        return
      else
        puts "Warning: No data.yaml or data/ directory found for #{@dataset_code}"
        @data = []
        return
      end
    end

    @data = YAML.load_file(data_path, aliases: true) || []
  end

  # Get the value of a key from an entry, handling nested keys with dot notation
  def get_value(entry, key)
    return nil unless entry

    if key.include?('.')
      parts = key.split('.')
      result = entry
      parts.each do |part|
        result = result[part] if result.is_a?(Hash)
        break unless result
      end
      result
    else
      entry[key]
    end
  end

  # Check if a key or combination of keys is unique across all entries
  def is_unique_key?(keys)
    return false if @data.empty?

    seen_values = Set.new

    @data.each do |entry|
      # For a combination of keys, create a composite key by joining values
      if keys.is_a?(Array) && keys.length > 1
        values = keys.map { |key| get_value(entry, key) }
        composite_key = values.join('|')
        return false if seen_values.include?(composite_key)
        seen_values.add(composite_key)
      else
        # For a single key
        key = keys.is_a?(Array) ? keys.first : keys
        value = get_value(entry, key)
        return false if seen_values.include?(value)
        seen_values.add(value)
      end
    end

    true
  end

  # Find a single key or minimal combination of keys that uniquely identifies entries
  def find_unique_key
    # First check if any single required key is unique
    @required_keys.each do |key|
      return [key] if is_unique_key?(key)
    end

    # If no single key is unique, try combinations of keys
    2.upto(@required_keys.length) do |i|
      @required_keys.combination(i).each do |combo|
        return combo if is_unique_key?(combo)
      end
    end

    # If we got here, no combination of required keys is unique
    # Try to find if any key in the data (required or not) could be unique
    all_keys = Set.new
    @data.each do |entry|
      entry.keys.each { |k| all_keys.add(k) }
    end

    all_keys.each do |key|
      next if @required_keys.include?(key) # Already checked
      return ["#{key} (not required)"] if is_unique_key?(key)
    end

    # If still no unique key, return nil
    nil
  end

  def analyze
    return "No data entries to analyze" if @data.empty?
    return "No required keys defined in schema" if @required_keys.empty?

    unique_key = find_unique_key

    if unique_key.nil?
      "No unique key or combination of keys found"
    elsif unique_key.length == 1
      "Unique key: #{unique_key.first}"
    else
      "Unique key combination: #{unique_key.join(' + ')}"
    end
  end
end

# Find all dataset directories
def find_datasets(base_path)
  datasets = []

  # Use the Find module to recursively search for directories
  Find.find(base_path) do |path|
    # Skip if not a directory
    next unless File.directory?(path)

    # Skip the base datasets directory itself
    next if path == base_path

    # Check if this directory contains a schema-data.yaml file
    if File.exist?(File.join(path, 'schema-data.yaml')) ||
       (File.directory?(File.join(path, 'data')) && !Dir.glob(File.join(path, 'data', '*.yaml')).empty?) ||
       File.exist?(File.join(path, 'data.yaml'))
      datasets << path
      # Skip subdirectories of this dataset
      Find.prune
    end
  end

  datasets
end

# Main script
if __FILE__ == $PROGRAM_NAME
  base_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'datasets'))
  datasets = find_datasets(base_path)

  puts "Found #{datasets.length} datasets"
  puts

  results = {}

  datasets.each do |dataset_path|
    dataset_code = File.basename(dataset_path)
    begin
      analyzer = DatasetAnalyzer.new(dataset_path)
      result = analyzer.analyze
      results[dataset_code] = result

      puts "Dataset: #{dataset_code}"
      puts "  Required keys: #{analyzer.required_keys.join(', ')}"
      puts "  #{result}"
      puts "  Data entries: #{analyzer.data.length}"
      puts
    rescue => e
      puts "Error processing dataset #{dataset_code}: #{e.message}"
      puts e.backtrace.first(3)
      results[dataset_code] = "Error: #{e.message}"
      puts
    end
  end

  # Summary
  puts "=== SUMMARY ==="
  results.each do |dataset, result|
    puts "#{dataset}: #{result}"
  end
end
