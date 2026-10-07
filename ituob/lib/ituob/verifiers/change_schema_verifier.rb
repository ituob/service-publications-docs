# frozen_string_literal: true

require 'json-schema'
require 'yaml'

module Ituob
  module Verifiers
    # Validates change files (patches) against +schema-change.yaml+.
    #
    # Each file in +datasets/{seed_issue}-{slug}/changes/+ must
    # conform to the schema-change.yaml JSON Schema. This verifier
    # walks every register catalogued in +Catalogs::Registers+,
    # reads its +changes/+ directory, and reports per-file errors.
    class ChangeSchemaVerifier < Base
      attr_reader :registers_catalog, :datasets_root

      def initialize(registers_catalog: Ituob::Catalogs::Registers,
                     datasets_root: default_datasets_root)
        super()
        @registers_catalog = registers_catalog
        @datasets_root = datasets_root
        @schema = load_schema
      end

      def verify
        result = Result.new(name: name)
        @registers_catalog.each_entry do |reg|
          next if reg.external?
          next unless reg.seed_path

          changes_dir = File.join(@datasets_root, '..', reg.seed_path, 'changes')
          next unless Dir.exist?(changes_dir)

          verify_directory(changes_dir, reg.register_id, result)
        end
        result
      end

      private

      def verify_directory(dir, register_id, result)
        Dir.children(dir)
           .select { |n| n.end_with?('.yaml', '.yml') }
           .sort
           .each do |name|
          path = File.join(dir, name)
          validate_file(path, register_id, name, result)
        end
      end

      def validate_file(path, register_id, name, result)
        data = Ituob::Support::Yaml.safe_load_file(path)
        errors = JSON::Validator.fully_validate(@schema, data || {},
                                                errors_as_objects: true)
        if errors.empty?
          result.stats[:valid] ||= 0
          result.stats[:valid] += 1
        else
          result.stats[:invalid] ||= 0
          result.stats[:invalid] += 1
          formatted = errors.map { |e| "#{e[:message]} at #{e[:fragment]}" }
          result.errors << "#{register_id}/#{name}: #{formatted.join('; ')}"
        end
      rescue StandardError => e
        result.stats[:invalid] ||= 0
        result.stats[:invalid] += 1
        result.errors << "#{register_id}/#{name}: #{e.class}: #{e.message}"
      end

      def load_schema
        path = File.join(@datasets_root, 'schema-change.yaml')
        schema = Ituob::Support::Yaml.safe_load_file(path)
        schema.delete('$schema')
        schema.delete('id')
        schema
      end

      def default_datasets_root
        File.expand_path('../../../../datasets', __dir__)
      end
    end
  end
end
