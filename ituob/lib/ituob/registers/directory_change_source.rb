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

      def self.for_register(register_id:, **options)
        source_class = register_id == 'F32_TDI' ? F32DirectoryChangeSource : self
        source_class.new(register_id: register_id, **options)
      end

      attr_reader :seed_path, :seed_issue

      # Source-level findings the replay cannot see because the file never
      # became a Change (or was filtered out): a repeated YAML key, a file
      # with no usable action, an unknown action type, a change dated before
      # the seed issue. Each is { kind:, file:, ob_issue:, detail: }, unique
      # per (kind, file, detail). Populated while the source is read.
      def issues
        @issues.values
      end

      # Repository-relative path of the change file a Change was read from,
      # or nil for the seed batch and for changes not read from a file.
      def path_for(change)
        @paths[change]
      end

      def initialize(register_id:, seed_path:, seed_issue:, key_field:)
        super(register_id: register_id)
        @seed_path = seed_path.to_s
        @seed_issue = seed_issue&.to_i
        @key_field = key_field.to_s
        @issues = {}
        @paths = {}.compare_by_identity
        @loaded_path = nil
      end

      # The amendment files dated before the seed issue: skipped by
      # +each_sorted+ because the seed supersedes them.
      def pre_seed_changes
        return [] unless @seed_issue

        each_amendment.select { |c| c.ob_issue_no && c.ob_issue_no < @seed_issue }
      end

      def each_sorted
        return enum_for(:each_sorted) unless block_given?

        yield seed_change if seed_change
        each_amendment do |c|
          # The seed list already embodies every amendment published
          # before the seed issue; replaying them would target entries
          # of a list state that no longer exists.
          if @seed_issue && c.ob_issue_no && c.ob_issue_no < @seed_issue
            record_issue('pre-seed', path_for(c), c.ob_issue_no,
                         'change is dated before the seed issue and is not replayed')
            next
          end

          yield c
        end
      end

      private

      def seed_change
        path = File.join(@seed_path, SEED_FILENAME)
        unless File.file?(path)
          record_issue('seed-unreadable', path, @seed_issue, 'seed data.yaml is missing')
          return nil
        end

        data = load_yaml(path)
        unless data.is_a?(Array)
          record_issue('seed-unreadable', path, @seed_issue, 'seed data.yaml is not a list of rows')
          return nil
        end

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
          unless hash.is_a?(Hash) && hash['type']
            record_issue('unreadable-change', path, nil, 'change file is not a mapping with a type')
            next
          end

          begin
            change = Change.from_hash(hash.merge('register' => hash['register'] || @register_id))
          rescue ArgumentError => e
            warn "skip #{path}: #{e.message}"
            record_issue('invalid-change', path, hash['ob_issue_no'], e.message)
            next
          end
          register_path(change, path)
          yield change
        end
      end

      def load_yaml(path)
        @loaded_path = path
        Ituob::Support::Yaml.duplicate_mapping_keys(path).each do |key|
          record_issue('duplicate-yaml-key', path, nil, "mapping key #{key.inspect} appears more than once")
        end
        Ituob::Support::Yaml.safe_load_file(path)
      end

      # Derived changes (a F.32 network replacement) are attributed to the
      # file being read.
      def register_path(change, path = @loaded_path)
        @paths[change] = path && relative_path(path)
        change
      end

      def record_issue(kind, path, ob_issue, detail)
        file = path && relative_path(path)
        @issues[[kind, file, detail]] ||= { kind: kind, file: file, ob_issue: ob_issue, detail: detail }
      end

      def relative_path(path)
        prefix = File.join(File.dirname(File.dirname(File.expand_path(@seed_path))), '')
        expanded = File.expand_path(path)
        expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : path
      end
    end
  end
end
