# frozen_string_literal: true

require 'yaml'
require 'ituob/catalogs'

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
        @key_field = key_field
        entry = Ituob::Catalogs::Registers.find(register_id)
        @fallback_key_fields = Array(entry&.fallback_key_fields)
        @seed_includes_seed_issue = entry&.seed_includes_seed_issue == true && entry.seed_issue == @seed_issue
      end

      def each_sorted
        return enum_for(:each_sorted) unless block_given?

        amendments = each_amendment
        amendments = amendments.to_a if @seed_includes_seed_issue
        seed = seed_change(amendments)
        yield seed if seed
        amendments.each do |c|
          # The seed list already embodies every amendment published
          # before the seed issue; replaying them would target entries
          # of a list state that no longer exists.
          next if @seed_issue && c.ob_issue_no && c.ob_issue_no < @seed_issue
          # Only catalogued annexes positioned on the issue date also
          # embody that issue's patches. Other seeds remain inclusive.
          next if @seed_includes_seed_issue && c.ob_issue_no == @seed_issue

          yield c
        end
      end

      private

      def seed_change(amendments)
        path = File.join(@seed_path, SEED_FILENAME)
        return nil unless File.file?(path)

        data = load_yaml(path)
        return nil unless data.is_a?(Array)

        supplement_seed(data, amendments) if @seed_includes_seed_issue

        Change.new(
          type: 'SEED',
          register_id: @register_id,
          identifier: { 'code' => '__seed__' },
          data: data,
          ob_issue_no: @seed_issue,
        )
      end

      # The annex fixes membership and populated fields, but its capture
      # may omit fields printed in that issue's amendments. Preserve those
      # fields without replaying removals or restoring absent entries.
      def supplement_seed(data, amendments)
        rows_by_key = data.select { |row| row.is_a?(Hash) }.group_by do |row|
          Strategies::Base.entry_key(row, @key_field, @fallback_key_fields)
        end
        amendments.each do |change|
          next unless change.ob_issue_no == @seed_issue
          next if change.action_type.destructive?

          Strategies::Base.rows_for(change, @key_field, @fallback_key_fields).each do |row|
            key = Strategies::Base.entry_key(row, @key_field, @fallback_key_fields)
            Array(rows_by_key[key]).each do |seed_row|
              row.each { |field, value| seed_row[field] = value if seed_row[field].nil? }
            end
          end
        end
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
