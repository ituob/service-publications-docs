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
      attr_reader :register_id, :key_field, :source

      def initialize(register_id:, key_field:, source:)
        @register_id = register_id.to_s
        @key_field = key_field.to_s
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
        Strategies::Resolver.apply(builder, change, @key_field)
      rescue Strategies::StrategyError => e
        msg = "skip #{change.type} #{change.identifier.to_hash.inspect} at OB #{change.ob_issue_no}: #{e.message}"
        builder.record_error(msg)
        warn "replay: #{msg}"
      rescue StandardError => e
        msg = "error #{change.type} #{change.identifier.to_hash.inspect} at OB #{change.ob_issue_no}: #{e.class}: #{e.message}"
        builder.record_error(msg)
        warn "replay: #{msg}"
      end
    end
  end
end
