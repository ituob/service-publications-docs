# frozen_string_literal: true

require "thor"
require "yaml"
require "json-schema"
require "colorize"
require "pathname"
require "fileutils"
require "ituob/dataset"

module Ituob
  module Commands
    class Dataset < Thor
      # Shared options across commands
      class_option :datasets_root, type: :string, aliases: "-r",
        desc: "Root directory containing the datasets collection (default: ./datasets)"
      class_option :metadata_schema, type: :string, aliases: "-m",
        desc: "Path to the metadata schema (default: ./schema-metadata.yaml)"
      class_option :verbose, type: :boolean, aliases: "-v",
        desc: "Show verbose output"

      desc "validate", "Validate ITU OB datasets against their schemas"
      option :dataset, type: :string, aliases: "-d",
        desc: "Specific dataset directory to validate within the datasets root"
      option :standalone, type: :string, aliases: "-s",
        desc: "Path to a standalone dataset directory to validate (outside the datasets collection)"

      def validate
        if options[:standalone]
          # Validate a standalone dataset
          standalone_dataset_path = resolve_path(options[:standalone])
          success = validate_dataset(Ituob::Dataset.new(standalone_dataset_path))
          exit(1) unless success
        else
          # Find all dataset directories or use the specified one
          dataset_dirs = if options[:dataset]
            [datasets_root.join(options[:dataset])]
          else
            datasets_root.children.select(&:directory?)
          end

          success = validate_datasets(dataset_dirs.map { |dir| Ituob::Dataset.new(dir) })
          exit(1) unless success
        end
      end

      desc "generate_manifest", "Generate a datasets.yaml manifest file listing all valid datasets"
      option :output, type: :string, aliases: "-o",
        desc: "Output file path (default: ./datasets.yaml)"

      def generate_manifest
        # Determine the output file path
        output_path = options[:output] ? resolve_path(options[:output]) : Pathname.new(File.join(Dir.pwd, "datasets.yaml"))

        # Find all dataset directories
        dataset_dirs = datasets_root.children.select(&:directory?)

        # Create manifest
        manifest = create_manifest(dataset_dirs.map { |dir| Ituob::Dataset.new(dir) })

        # Write manifest to file
        File.write(output_path, manifest.to_yaml)

        puts "Manifest generated at #{output_path}".green
      end

      private

      # Helper methods for resolving paths
      def datasets_root
        @datasets_root ||= options[:datasets_root] ?
          resolve_path(options[:datasets_root]) :
          Pathname.new(File.join(Dir.pwd, "datasets"))
      end

      def metadata_schema_path
        @metadata_schema_path ||= options[:metadata_schema] ?
          resolve_path(options[:metadata_schema]) :
          Pathname.new(File.join(Dir.pwd, "datasets", "schema-metadata.yaml"))
      end

      def resolve_path(path_str)
        path = Pathname.new(path_str)
        path.absolute? ? path : Pathname.new(File.join(Dir.pwd, path_str))
      end

      # Manifest creation logic
      def create_manifest(datasets)
        puts "Analyzing #{datasets.size} datasets for manifest...".cyan if options[:verbose]

        valid_datasets = datasets.select(&:valid_structure?).map(&:info)

        # Sort datasets by their directory name
        valid_datasets.sort_by! { |dataset| dataset["directory"] }

        { "datasets" => valid_datasets }
      end

      # Dataset validation logic
      def validate_datasets(datasets)
        puts "Validating #{datasets.size} datasets...".cyan

        results = datasets.map { |dataset| validate_dataset(dataset) }

        success_count = results.count(true)
        failure_count = results.count(false)

        print_summary(success_count, failure_count)

        failure_count == 0
      end

      def validate_dataset(dataset)
        puts "\nValidating dataset: #{dataset.name}".cyan

        metadata_success, metadata_error = validate_metadata(dataset)
        data_success, data_error = validate_data(dataset)

        if metadata_success
          puts "  ✓ metadata.yaml is valid".green
        else
          log_error("metadata.yaml validation failed", metadata_error)
        end

        if data_success
          puts "  ✓ data validation passed".green
        else
          if data_error.is_a?(Array)
            log_error("Data validation failed with multiple errors:")
            data_error.each do |err|
              log_error("  - #{err}")
            end
          else
            detailed_errors = extract_validation_errors(data_error)

            if detailed_errors && !detailed_errors.empty?
              log_error("Data validation failed:")
              detailed_errors.each do |err|
                # Format the error message to help locate the issue
                log_error("  - #{err}")
              end
            else
              log_error("Data validation failed", data_error)
            end
          end
        end

        metadata_success && data_success
      end

      def validate_metadata(dataset)
        dataset.validate_metadata(metadata_schema_path)
      end

      def validate_data(dataset)
        dataset.validate_data
      end

      # Extract specific validation error details from JSON Schema errors
      def extract_validation_errors(error_message)
        return nil unless error_message.is_a?(String)

        # Common patterns in JSON Schema validation errors
        patterns = [
          # Match property errors like "The property '#/prop1/prop2' did not..."
          /The property '#\/([^']+)' ([^:]+)/,
          # Match schema errors
          /Schema: ([^,]+), Instance: ([^,]+)/,
          # Match type errors
          /of type ([^ ]+) did not match the following type: ([^ ]+)/
        ]

        # Try to extract structured error information
        matches = patterns.map { |pattern| error_message.match(pattern) }.compact

        if matches.any?
          return [error_message]
        end

        # If we can't extract structured errors, parse the JSON Schema error message
        if error_message.include?("did not contain a required property")
          property = error_message.match(/did not contain a required property of '([^']+)'/)
          return ["Missing required property: #{property[1]}"] if property
        end

        if error_message.include?("The schema did not match")
          return ["Schema validation failed: #{error_message}"]
        end

        # If all else fails, return the original message
        [error_message]
      end

      # Logging and output utilities
      def log_error(message, exception = nil)
        puts "  ✗ #{message}".red

        if exception && options[:verbose]
          if exception.respond_to?(:message)
            error_lines = exception.message.split("\n")
            error_lines.each do |line|
              puts "    #{line}".yellow
            end
          elsif exception.is_a?(String)
            puts "    #{exception}".yellow
          end
        end
      end

      def print_summary(success_count, failure_count)
        puts "\nValidation Summary:".cyan
        puts "  Passed: #{success_count}".green
        puts "  Failed: #{failure_count}".red
      end
    end
  end
end
