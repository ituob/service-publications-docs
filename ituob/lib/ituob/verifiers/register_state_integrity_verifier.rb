# frozen_string_literal: true

require 'ituob/support'
require 'ituob/registers'
require 'ituob/catalogs'
require 'json'

module Ituob
  module Verifiers
    # Checks the row-derived keys of every edition rendered by the site.
    # Reporting is read-only: incomplete keys remain visible as data defects.
    class RegisterStateIntegrityVerifier < Base
      OPTIONAL_KEY_PARTS = {
        'F32_TDI' => { 'network_code' => :when_office_code_complete }.freeze
      }.freeze

      DEFAULT_ROOT = File.expand_path('../../../..', __dir__).freeze

      # +allowlist+ is the reviewed set of replay findings that exist on main
      # today, each { register:, ob_issue:, file:, kind:, detail: }. Any
      # replay finding outside it fails the gate.
      def initialize(registers_catalog: Ituob::Catalogs::Registers, root: DEFAULT_ROOT, allowlist: [], snapshots_root: nil)
        super()
        @registers_catalog = registers_catalog
        @root = root
        @snapshots_root = snapshots_root
        @allowlist = allowlist.map { |item| self.class.finding_key(item) }
      end

      FINDING_FIELDS = %i[register ob_issue file kind detail].freeze

      def self.finding_key(item)
        FINDING_FIELDS.map { |field| (item[field] || item[field.to_s]).to_s }
      end

      # Every replay finding of one register: lenient replay behaviour, skipped
      # and failed changes (from the current state, which accumulates all of
      # them) and the source-level problems that stop a file becoming a change.
      def self.replay_findings(replay, state)
        from_state = state.issues.map do |issue|
          change = issue[:change]
          { register: replay.register_id, ob_issue: change.ob_issue_no, file: replay.source.path_for(change),
            kind: issue[:kind], detail: issue[:detail] }
        end
        from_source = replay.source.issues.map do |issue|
          { register: replay.register_id, ob_issue: issue[:ob_issue], file: issue[:file],
            kind: issue[:kind], detail: issue[:detail] }
        end
        (from_state + from_source).sort_by { |finding| finding_key(finding) }
      end

      # Shared with snapshot generation so the gate checks the same replay.
      def self.build_replay(entry, root: DEFAULT_ROOT)
        return nil if entry.external? || entry.seed_path.nil?

        source = Ituob::Registers::DirectoryChangeSource.for_register(
          register_id: entry.register_id,
          seed_path: File.expand_path(entry.seed_path, root),
          seed_issue: entry.seed_issue,
          seed_includes_seed_issue: entry.seed_includes_seed_issue,
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
          states = replay.build_all_states
          states.each_value do |state|
            result.merge!(verify_state(state, register: register))
            verify_snapshot(state, register, result) if @snapshots_root
          end
          result.merge!(verify_findings(self.class.replay_findings(replay, states.fetch(nil)), register))
        end
        result
      end

      # Fails every finding that is not in the allowlist (one allowlist entry
      # covers one occurrence). Allowlist entries that no longer occur are
      # warnings: the data was fixed, so the entry should be pruned.
      def verify_findings(findings, register)
        result = Result.new(name: name, stats: { replay_findings: findings.length, replay_findings_allowed: 0 })
        remaining = @allowlist.select { |key| key.first == register.register_id }.tally
        findings.each do |finding|
          key = self.class.finding_key(finding)
          if remaining[key].to_i.positive?
            remaining[key] -= 1
            result.stats[:replay_findings_allowed] += 1
          else
            result.errors << "#{register.register_id}: OB #{finding[:ob_issue] || '-'} #{finding[:file] || '-'}: " \
                             "replay #{finding[:kind]}: #{finding[:detail]} (not in the reviewed allowlist)"
          end
        end
        remaining.each do |key, count|
          result.warnings << "#{register.register_id}: allowlist entry no longer occurs (x#{count}): #{key.inspect}" if count.positive?
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

      def verify_snapshot(state, register, result)
        edition = state.at_ob_issue || 'current'
        filename = state.at_ob_issue ? "at-#{state.at_ob_issue}.json" : 'current.json'
        path = File.join(@snapshots_root, register.slug, filename)
        snapshot = JSON.parse(File.read(path))
        return if snapshot == state.to_snapshot(slug: register.slug)

        result.errors << "#{register.register_id}: OB #{edition} #{path}: snapshot does not match replayed state"
      rescue SystemCallError, JSON::ParserError => e
        result.errors << "#{register.register_id}: OB #{edition} #{path}: snapshot unreadable: #{e.message}"
      end

      def entry_key(row, fields, fallbacks = [])
        Ituob::Registers::Strategies::Base.entry_key(row, fields, fallbacks)
      end

      def blank_key?(key)
        key.nil? || key.gsub(/[[:space:]\u00a0]/, '').empty?
      end

      def key_failures(row, stored_key, key, counts, register)
        failures = []
        if register.register_id == 'F32_TDI' && !entry_key(row, 'office_code').to_s.match?(/\A[A-Z]{4}\z/)
          failures << '(e) office allocation requires a full four-letter destination indicator'
        end
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
