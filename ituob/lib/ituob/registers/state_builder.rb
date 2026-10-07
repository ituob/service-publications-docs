# frozen_string_literal: true

module Ituob
  module Registers
    # Mutable working state used internally by Replay. Strategies
    # mutate this; Replay freezes it into a State when done.
    #
    # Tracks four structures:
    #   * entries        — Hash { key(String) => row(Hash) }
    #   * lapsed_keys    — Set of keys marked LIR
    #   * deleted_keys   — Set of keys removed via SUP/DEL
    #   * supersessions  — Hash { old_key => new_key } for SUP redirects
    #   * lapse_reasons  — Hash { key => reason_hash }
    class StateBuilder
      include Ituob::Support::DeepFreeze

      attr_reader :register_id, :entries, :lapsed_keys, :deleted_keys,
                  :supersessions, :lapse_reasons, :history, :errors

      def initialize(register_id)
        @register_id = register_id
        @entries = {}
        @lapsed_keys = Set.new
        @deleted_keys = Set.new
        @supersessions = {}
        @lapse_reasons = {}
        @history = []
        @errors = []
      end

      def set_entry(key, row)
        @entries[key.to_s] = row
      end

      def remove_entry(key)
        @entries.delete(key.to_s)
      end

      def mark_lapsed(key, reason: nil)
        @lapsed_keys << key.to_s
        @lapse_reasons[key.to_s] = reason if reason
      end

      def clear_lapsed(key)
        @lapsed_keys.delete(key.to_s)
        @lapse_reasons.delete(key.to_s)
      end

      def mark_deleted(key)
        @deleted_keys << key.to_s
      end

      def clear_deleted(key)
        @deleted_keys.delete(key.to_s)
      end

      def record_supersession(old_key, new_key)
        @supersessions[old_key.to_s] = new_key.to_s
      end

      def record_history(change)
        @history << change
      end

      def record_error(message)
        @errors << message
      end

      def find_key_by_query(identifier, key_field)
        match = @entries.find do |k, row|
          identifier.matches?(row, key_field)
        end
        match && match.first
      end

      # Snapshot the builder's mutable state into an immutable State.
      #
      # Deep-freezes the entries hash at this layer rather than relying
      # on State to do it. The builder's working entries are still
      # mutable afterwards — only the State is frozen. This prevents
      # future refactors of State from silently leaking mutability back
      # into already-emitted snapshots.
      def to_state(at_ob_issue)
        State.new(
          register_id: @register_id,
          at_ob_issue: at_ob_issue,
          entries: deep_freeze(@entries.dup),
          lapsed_keys: @lapsed_keys.dup,
          deleted_keys: @deleted_keys.dup,
          history: @history.dup,
          error_count: @errors.length,
          errors: @errors.dup,
          lapse_reasons: @lapse_reasons.dup,
        )
      end
    end
  end
end
