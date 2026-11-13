# frozen_string_literal: true

module Ituob
  module Registers
    # Pure functional replay service. Builds a register's state at a
    # point in time from the seed batch + ordered OB amendments.
    #
    # Usage:
    #
    #   source = Ituob::Registers::DirectoryChangeSource.new(
    #     register_id: "F1", seed_path: ".../datasets/669-F.1",
    #     seed_issue: 669, key_field: "code",
    #   )
    #   replay = Ituob::Registers::Replay.new(
    #     register_id: "F1", key_field: "code", source: source,
    #   )
    #
    #   replay.at_issue(1180)   # => State as of end of OB 1180
    #   replay.current         # => State with all changes applied
    #   replay.empty?          # false
    #
    # Replay is idempotent and side-effect-free. Strategies mutate a
    # private StateBuilder; Replay freezes the result.
    class Replay
      attr_reader :register_id, :key_field, :fallback_key_fields, :source

      def initialize(register_id:, key_field:, source:, fallback_key_fields: [])
        @register_id = register_id.to_s
        @key_field = key_field
        @fallback_key_fields = Array(fallback_key_fields)
        @source = source
      end

      # State at end of OB issue +ob_issue+ (inclusive).
      def at_issue(ob_issue)
        builder = new_builder
        source.each_until(ob_issue) do |change|
          apply_change(builder, change)
        end
        builder.to_state(ob_issue)
      end

      # State with every available change applied.
      def current
        at_issue(nil)
      end

      # State at the seed issue (just the seed batch).
      def at_seed
        at_issue(source.seed_issue)
      end

      # Structured diff between two point-in-time states.
      #
      # Returns a +StateDiff+ with added/removed/modified keys plus
      # keys that became lapsed or were reactivated between the two
      # OB issues. Both endpoints are inclusive.
      #
      # Raises +ArgumentError+ if either issue is nil.
      def diff(from_issue, to_issue)
        raise ArgumentError, 'from_issue is required' if from_issue.nil?
        raise ArgumentError, 'to_issue is required' if to_issue.nil?

        StateDiff.between(at_issue(from_issue), at_issue(to_issue))
      end

      # Build a state snapshot at every touched OB issue in ONE pass.
      # Returns a Hash { ob_issue => State }. Much more efficient than
      # calling +at_issue(N)+ repeatedly for snapshot generation.
      #
      # The returned hash always includes an entry for the seed issue
      # (if set) and the last issue seen (under key +nil+ for "current").
      def build_all_states
        builder = new_builder
        states = {}
        prev_issue = nil

        source.each_sorted do |change|
          issue = change.ob_issue_no

          # BEFORE applying this change: if we've crossed an issue
          # boundary, capture the PREVIOUS issue's final state.
          # This ensures the state for issue N includes only changes
          # with ob_issue_no <= N.
          if issue && prev_issue && issue != prev_issue
            states[prev_issue] = builder.to_state(prev_issue)
          end

          apply_change(builder, change)
          prev_issue = issue if issue
        end

        # Capture the last issue's state.
        states[prev_issue] = builder.to_state(prev_issue) if prev_issue

        # Capture current (post-last-change) state under nil key.
        states[nil] = builder.to_state(nil)

        states
      end

      private

      def new_builder
        StateBuilder.new(@register_id)
      end

      def apply_change(builder, change)
        builder.record_history(change)
        Strategies::Resolver.apply(builder, change, @key_field, @fallback_key_fields) do |e|
          report_skip(builder, change, e)
        end
      rescue Strategies::StrategyError => e
        report_skip(builder, change, e)
      rescue StandardError => e
        msg = "error #{change.type} #{change.identifier.to_hash.inspect} at OB #{change.ob_issue_no}: #{e.class}: #{e.message}"
        builder.record_error(msg)
        warn "replay: #{msg}"
      end

      # A SUP published in the seed issue itself, for a key the seed list
      # no longer holds, is already reflected: the seed is the post-issue
      # list. Accepted only with evidence that it is a real removal and
      # not a typo: the seed has been applied, no change at or after the
      # seed issue has touched the key (so not a second SUP), and an earlier edition (a pre-seed change) names the
      # key. The change stays in +history+, touches no key, and is
      # listed in +reflected_in_seed+ instead of +errors+. Only SUP's
      # absence check raises a StrategyError here.
      def reflected_in_seed?(builder, change, error)
        seed = source.seed_issue
        key = error.key
        return false unless seed.is_a?(Integer) && seed.positive?
        return false unless change.type.to_s == 'SUP' && change.ob_issue_no == seed
        return false if key.nil? || builder.reflected?(key)
        return false unless builder.history.any?(&:seed?)
        return false if (builder.key_history[key.to_s] || []).any? { |c| c.ob_issue_no.to_i >= seed }

        pre_seed_keys.include?(key.to_s)
      end

      # Keys named by changes published before the seed issue.
      def pre_seed_keys
        @pre_seed_keys ||= source.pre_seed_changes.each_with_object(Set.new) do |c, keys|
          Strategies::Base.rows_for(c, @key_field, @fallback_key_fields).each do |row|
            keys << Strategies::Base.entry_key(row, @key_field, @fallback_key_fields).to_s
          end
          keys << c.identifier.code.to_s if c.identifier.direct?
        end
      end

      # Returns true when the change was recorded as a skip, false when it
      # was accepted as reflected in the seed.
      def report_skip(builder, change, error)
        if reflected_in_seed?(builder, change, error)
          builder.record_reflected(change, error.key)
          return false
        end

        msg = "skip #{change.type} #{change.identifier.to_hash.inspect} at OB #{change.ob_issue_no}: #{error.message}"
        builder.record_error(msg)
        warn "replay: #{msg}"
        true
      end
    end
  end
end
