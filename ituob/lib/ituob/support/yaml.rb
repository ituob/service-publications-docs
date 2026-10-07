# frozen_string_literal: true

require 'yaml'

module Ituob
  module Support
    # Stateless utility for reading OB-style YAML safely.
    #
    # All OB YAML files (catalogs, schemas fragments, change files,
    # seed data) use the same feature set: aliases permitted, plus
    # Date/Time/DateTime/Symbol deserialization. Centralizing the
    # call here means a single source of truth for the policy.
    #
    # Files are always read as UTF-8.
    module Yaml
      DEFAULT_PERMITTED_CLASSES = [Date, Time, DateTime, Symbol].freeze

      module_function

      # Read +path+ as UTF-8 and parse it as YAML. Returns nil for
      # empty files (mirrors +YAML.safe_load+ behaviour).
      def safe_load_file(path)
        safe_load_string(File.read(path, encoding: 'utf-8'))
      end

      # Parse a YAML string with the project's standard policy.
      def safe_load_string(contents)
        YAML.safe_load(contents,
                       aliases: true,
                       permitted_classes: DEFAULT_PERMITTED_CLASSES)
      end
    end
  end
end
