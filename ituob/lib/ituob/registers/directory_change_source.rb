# frozen_string_literal: true

require 'yaml'

module Ituob
  module Registers
    # ChangeSource backed by the on-disk directory layout:
    #
    #   datasets/{seed_issue}-{slug}/
    #     data.yaml          # SEED batch (the original publication)
    #     changes/           # subsequent patches
    #       {ob_issue}-{seq}-{ACTION}-{key}.yaml
    #
    # Each patch file validates (structurally, not via JSON Schema
    # here) against schema-change.yaml. The seed batch are wrapped in
    # a synthetic Change with type=SEED at the seed_issue.
    class DirectoryChangeSource < ChangeSource
      SEED_FILENAME = 'data.yaml'
      CHANGES_SUBDIR = 'changes'

      attr_reader :seed_path, :seed_issue

      def initialize(register_id:, seed_path:, seed_issue:, key_field:)
        super(register_id: register_id)
        @seed_path = seed_path.to_s
        @seed_issue = seed_issue&.to_i
        @key_field = key_field.to_s
      end

      def each_sorted
        return enum_for(:each_sorted) unless block_given?

        yield seed_change if seed_change
        each_amendment { |c| yield c }
      end

      private

      def seed_change
        path = File.join(@seed_path, SEED_FILENAME)
        return nil unless File.file?(path)

        data = load_yaml(path)
        return nil unless data.is_a?(Array)

        Change.new(
          type: 'SEED',
          register_id: @register_id,
          identifier: { 'code' => '__seed__' },
          data: data,
          ob_issue_no: @seed_issue,
        )
      end

      def each_amendment
        return enum_for(:each_amendment) unless block_given?

        dir = File.join(@seed_path, CHANGES_SUBDIR)
        return unless Dir.exist?(dir)

        Dir.children(dir)
           .select { |n| n.end_with?('.yaml', '.yml') }
           .sort
           .each do |name|
          path = File.join(dir, name)
          hash = load_yaml(path)
          next unless hash.is_a?(Hash) && hash['type']

          begin
            yield Change.from_hash(hash.merge('register' => hash['register'] || @register_id))
          rescue ArgumentError => e
            warn "skip #{path}: #{e.message}"
          end
        end
      end

      def load_yaml(path)
        Ituob::Support::Yaml.safe_load_file(path)
      end
    end
  end
end
