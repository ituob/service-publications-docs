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

      def initialize(register_id:, seed_path:, seed_issue:, key_field:, seed_includes_seed_issue: false)
        super(register_id: register_id)
        @seed_path = seed_path.to_s
        @seed_issue = seed_issue&.to_i
        @key_field = key_field.to_s
        @seed_includes_seed_issue = seed_includes_seed_issue == true
      end

      # The amendment files dated before the seed issue: skipped by
      # +each_sorted+ because the seed supersedes them.
      def pre_seed_changes
        return [] unless @seed_issue

        each_amendment.select { |c| c.ob_issue_no && c.ob_issue_no < @seed_issue }
      end

      def each_sorted
        return enum_for(:each_sorted) unless block_given?

        seed = seed_change
        yield seed if seed
        seed_rows = Array(seed&.data).to_h do |row|
          [Strategies::Base.entry_key(row, @key_field), row]
        end
        replayed_keys = [] if @seed_includes_seed_issue
        each_amendment do |c|
          # The catalog flag permits exclusion only when the seed proves
          # the whole amendment redundant, including every nested field.
          next if @seed_issue && c.ob_issue_no &&
            (c.ob_issue_no < @seed_issue ||
             (@seed_includes_seed_issue && c.ob_issue_no == @seed_issue &&
               seed && (change_keys(c) & replayed_keys).empty? && included_in_seed?(c, seed_rows)))

          replayed_keys.concat(change_keys(c)) if replayed_keys && c.ob_issue_no == @seed_issue
          yield c
        end
      end

      private

      def change_keys(change)
        rows = Strategies::Base.rows_for(change, @key_field)
        keys = rows.map { |row| Strategies::Base.entry_key(row, @key_field) }
        keys = [change.identifier.code] if keys.empty? && change.identifier&.direct?
        keys
      end

      def included_in_seed?(change, seed_rows)
        rows = Strategies::Base.rows_for(change, @key_field)
        if change.sup?
          keys = change_keys(change)
          return !keys.empty? && keys.all? { |key| !seed_rows.key?(key) }
        end
        return false unless change.add? || change.lir?
        return false if rows.empty?

        rows.all? do |row|
          seed_row = seed_rows[Strategies::Base.entry_key(row, @key_field)]
          fields_included?(row, seed_row)
        end
      end

      def fields_included?(patch, seed)
        return patch == seed unless patch.is_a?(Hash)
        return false unless seed.is_a?(Hash)

        patch.all? do |field, value|
          seed.key?(field) && fields_included?(value, seed[field])
        end
      end

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
