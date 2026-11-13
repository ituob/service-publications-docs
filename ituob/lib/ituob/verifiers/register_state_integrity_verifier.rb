# frozen_string_literal: true

require 'ituob/support'
require 'ituob/registers'
require 'ituob/catalogs'

module Ituob
  module Verifiers
    # Checks the row-derived keys of every edition rendered by the site.
    # Reporting is read-only: incomplete keys remain visible as data defects.
    class RegisterStateIntegrityVerifier < Base
      OPTIONAL_KEY_PARTS = {
        'F32_TDI' => { 'network_code' => :when_office_code_complete }.freeze
      }.freeze

      DEFAULT_ROOT = File.expand_path('../../../..', __dir__).freeze

      def initialize(registers_catalog: Ituob::Catalogs::Registers, root: DEFAULT_ROOT)
        super()
        @registers_catalog = registers_catalog
        @root = root
      end

      # Shared with snapshot generation so the gate checks the same replay.
      def self.build_replay(entry, root: DEFAULT_ROOT)
        return nil if entry.external? || entry.seed_path.nil?

        source = Ituob::Registers::DirectoryChangeSource.new(
          register_id: entry.register_id,
          seed_path: File.expand_path(entry.seed_path, root),
          seed_issue: entry.seed_issue,
          key_field: entry.key_field
        )
        Ituob::Registers::Replay.new(
          register_id: entry.register_id,
          key_field: entry.key_field,
          source: source,
          fallback_key_fields: entry.fallback_key_fields
        )
      end

      def verify
        result = Result.new(name: name, stats: { registers_checked: 0 })
        @registers_catalog.each_entry do |register|
          replay = self.class.build_replay(register, root: @root)
          next unless replay

          result.stats[:registers_checked] += 1
          # build_all_states includes replay.current under nil; check it once.
          replay.build_all_states.each_value do |state|
            result.merge!(verify_state(state, register: register))
          end
        end
        result
      end

      def verify_state(state, register:)
        result = Result.new(name: name)
        derived = state.active_entries.transform_values do |row|
          entry_key(row, register.key_field, register.fallback_key_fields)
        end
        counts = derived.values.tally
        invalid_count = 0
        state.active_entries.each do |stored_key, row|
          failures = key_failures(row, stored_key, derived[stored_key], counts, register)
          next if failures.empty?

          invalid_count += 1
          failures.each do |failure|
            result.errors << "#{register.register_id}: OB #{state.at_ob_issue || 'current'} " \
                             "key #{stored_key.inspect}: #{failure}"
          end
        end
        result.stats = {
          states_checked: 1, entries_checked: state.entry_count,
          invalid_entries: invalid_count
        }
        result.details << {
          register_id: register.register_id, slug: register.slug,
          ob_issue: state.at_ob_issue || 'current', entry_count: state.entry_count,
          invalid_entry_count: invalid_count
        }
        result
      end

      private

      def entry_key(row, fields, fallbacks = [])
        Ituob::Registers::Strategies::Base.entry_key(row, fields, fallbacks)
      end

      def blank_key?(key)
        key.nil? || key.gsub(/[[:space:]\u00a0]/, '').empty?
      end

      def key_failures(row, stored_key, key, counts, register)
        failures = []
        failures << '(a) blank key' if blank_key?(key)
        failures << '(b) NBSP in key' if key&.include?("\u00a0")
        if Array(register.key_field).length > 1
          Array(register.key_field).each do |field|
            next unless blank_key?(entry_key(row, field))
            next if optional_part?(register.register_id, field, row)

            failures << "(c) blank composite part #{field}"
          end
        end
        failures << "(d) stored key does not match derived key #{key.inspect}" if stored_key != key
        failures << "(d) duplicate derived key #{key.inspect} (#{counts[key]} active entries)" if counts[key] > 1
        failures
      end

      def optional_part?(register_id, field, row)
        predicate = OPTIONAL_KEY_PARTS.dig(register_id, field.to_s)
        predicate && send(predicate, row)
      end

      def when_office_code_complete(row)
        entry_key(row, 'office_code').to_s.match?(/\A[A-Za-z]{4}\z/)
      end
    end
  end
end
