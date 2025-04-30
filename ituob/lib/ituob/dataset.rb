# frozen_string_literal: true

require "yaml"
require "json-schema"
require "pathname"

module Ituob
  # Represents an ITU OB dataset with properties and validation methods
  class Dataset
    attr_reader :path, :name

    # Initialize a dataset with its path
    # @param path [String, Pathname] path to the dataset directory
    def initialize(path)
      @path = Pathname.new(path)
      @name = @path.basename.to_s
    end

    # Check if this is a valid dataset with all required components
    # @return [Boolean] true if the dataset is valid
    def valid_structure?
      metadata_path.exist? && schema_data_path.exist? && has_data?
    end

    # Check if the dataset has data files
    # @return [Boolean] true if the dataset has data
    def has_data?
      data_path.exist? || (data_dir.exist? && data_dir.directory? && !data_files.empty?)
    end

    # Get path to metadata.yaml
    # @return [Pathname] path to metadata.yaml
    def metadata_path
      @metadata_path ||= @path.join("metadata.yaml")
    end

    # Get path to schema-data.yaml
    # @return [Pathname] path to schema-data.yaml
    def schema_data_path
      @schema_data_path ||= @path.join("schema-data.yaml")
    end

    # Get path to data.yaml
    # @return [Pathname] path to data.yaml
    def data_path
      @data_path ||= @path.join("data.yaml")
    end

    # Get path to data directory
    # @return [Pathname] path to data directory
    def data_dir
      @data_dir ||= @path.join("data")
    end

    # Get all YAML files in the data directory
    # @return [Array<Pathname>] array of YAML file paths
    def data_files
      return [] unless data_dir.exist? && data_dir.directory?
      @data_files ||= data_dir.children.select { |p| p.extname =~ /\.ya?ml$/ }
    end

    # Load metadata content
    # @return [Hash] metadata content
    def metadata
      @metadata ||= safe_load_yaml(metadata_path)
    end

    # Load schema-data content
    # @return [Hash] schema content
    def schema_data
      @schema_data ||= safe_load_yaml(schema_data_path)
    end

    # Load data content (from data.yaml or combined from data/*.yaml)
    # @return [Hash, Array] data content
    def data
      if data_path.exist?
        @data ||= safe_load_yaml(data_path)
      elsif data_dir.exist? && data_dir.directory?
        @data ||= data_files.map { |f| safe_load_yaml(f) }
      else
        nil
      end
    end

    # Get dataset title from metadata
    # @return [String] dataset title or directory name if not available
    def title
      metadata&.dig("title", "en") || @name
    rescue
      @name
    end

    # Get information about the dataset for manifest
    # @return [Hash] dataset information
    def info
      {
        "directory" => @name,
        "title" => title,
        "has_data_file" => data_path.exist?,
        "has_data_directory" => (data_dir.exist? && data_dir.directory?)
      }
    end

    # Validate metadata against schema
    # @param schema_path [String, Pathname] path to metadata schema
    # @return [Boolean, Array] true if valid, or array of errors if invalid
    def validate_metadata(schema_path)
      return [false, "metadata.yaml not found"] unless metadata_path.exist?
      return [false, "Metadata schema not found at #{schema_path}"] unless File.exist?(schema_path)

      # Check for schema directive
      schema_directive_present, error = check_schema_directive(metadata_path, "../schema-metadata.yaml")
      return [false, error] unless schema_directive_present

      begin
        schema = safe_load_yaml(schema_path)
        # Remove $schema to avoid validation against the meta-schema
        schema.delete('$schema')

        errors = JSON::Validator.fully_validate(schema, metadata, errors_as_objects: true)

        if errors.empty?
          [true, nil]
        else
          formatted_errors = errors.map do |error|
            "#{error[:message]} at #{error[:fragment]}"
          end
          [false, formatted_errors.join("\n")]
        end
      rescue => e
        [false, e.message]
      end
    end

    # Validate data against schema-data
    # @return [Boolean, Array] true if valid, or array of [filename, error] pairs if invalid
    def validate_data
      return [false, "schema-data.yaml not found"] unless schema_data_path.exist?

      begin
        schema = schema_data.dup
        # Remove $schema to avoid validation against the meta-schema
        schema.delete('$schema')

        if data_path.exist?
          # Check for schema directive in data.yaml
          schema_directive_present, error = check_schema_directive(data_path, "schema-data.yaml")
          return [false, error] unless schema_directive_present

          validate_file_against_schema(data_path, schema)
        elsif data_dir.exist? && data_dir.directory?
          validate_data_directory(schema)
        else
          [false, "Neither data.yaml nor data/ directory found"]
        end
      rescue => e
        [false, "Error processing schema-data.yaml: #{e.message}"]
      end
    end

    private

    # Safely load YAML file with aliases enabled
    # @param file_path [Pathname] path to file
    # @return [Hash, Array] loaded YAML content
    def safe_load_yaml(file_path)
      YAML.load_file(file_path, aliases: true)
    end

    # Validate a single file against schema
    # @param file_path [Pathname] path to file
    # @param schema [Hash] schema to validate against
    # @return [Boolean, String] true if valid, or error message if invalid
    def validate_file_against_schema(file_path, schema)
      begin
        # Check for schema directive in data files within data/ directory
        if file_path.dirname.basename.to_s == "data"
          schema_directive_present, error = check_schema_directive(file_path, "../schema-data.yaml")
          return [false, error] unless schema_directive_present
        end

        data = safe_load_yaml(file_path)

        # Use fully_validate to get detailed error information
        errors = JSON::Validator.fully_validate(schema, data, errors_as_objects: true)

        if errors.empty?
          [true, nil]
        else
          # Format errors with path information
          error_messages = errors.map do |error|
            path = error[:fragment].empty? ? "root" : error[:fragment]
            "#{file_path.basename}: Error at #{path} - #{error[:message]}"
          end
          [false, error_messages.join("\n")]
        end
      rescue => e
        [false, "#{file_path.basename}: #{e.message}"]
      end
    end

    # Validate all files in data directory
    # @param schema [Hash] schema to validate against
    # @return [Boolean, Array] true if all valid, or array of [filename, error] pairs if any invalid
    def validate_data_directory(schema)
      if data_files.empty?
        return [false, "No YAML files found in data/ directory"]
      end

      errors = []

      data_files.each do |file|
        success, error = validate_file_against_schema(file, schema)
        errors << error unless success
      end

      errors.empty? ? [true, nil] : [false, errors]
    end

    # Check if a file has the correct schema directive
    # @param file_path [Pathname] path to the file
    # @param expected_schema_path [String] expected schema path
    # @return [Boolean, String] true if directive exists, or error message if not
    def check_schema_directive(file_path, expected_schema_path)
      # Read the first line of the file to check for the schema directive
      first_line = File.open(file_path, &:readline).strip rescue ""

      # Check if the directive exists with the correct schema
      directive_pattern = /^# yaml-language-server: \$schema=#{Regexp.escape(expected_schema_path)}$/

      if first_line.match?(directive_pattern)
        [true, nil]
      else
        [false, "#{file_path.basename}: Missing or incorrect schema directive. Expected '# yaml-language-server: $schema=#{expected_schema_path}'"]
      end
    end
  end
end
