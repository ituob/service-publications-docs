# frozen_string_literal: true

module Ituob
  module Registers
    # Immutable value object: the replayed state of a register at a
    # point in time. Returned by Replay service.
    #
    # All fields are deep-frozen on construction — the entries hash,
    # its individual row values, the lapsed/deleted key sets, and the
    # history array are all immutable after the State is returned.
    class State
      include Ituob::Support::DeepFreeze

      attr_reader :register_id, :at_ob_issue, :entries, :lapsed_keys,
                  :deleted_keys, :history, :error_count, :errors,
                  :lapse_reasons

      def initialize(register_id:, at_ob_issue:, entries:,
                     lapsed_keys:, deleted_keys:, history:,
                     error_count: 0, errors: [], lapse_reasons: {})
        @register_id = register_id
        @at_ob_issue = at_ob_issue
        # Deep-freeze: freeze the hash AND every row value inside it.
        @entries = deep_freeze(entries)
        @lapsed_keys = lapsed_keys.freeze
        @deleted_keys = deleted_keys.freeze
        @history = history.freeze
        @error_count = error_count.to_i
        @errors = Array(errors).map(&:freeze).freeze
        @lapse_reasons = deep_freeze(lapse_reasons)
        # Compute active_entries BEFORE freezing the State itself.
        @active_entries = @entries.reject { |k, _| @lapsed_keys.include?(k) }
        freeze
      end

      def active_entries
        @active_entries
      end

      def active_keys = active_entries.keys
      def entry_count = active_entries.length

      def entry_for(key)
        @entries[key.to_s]
      end

      def has_key?(key)
        @entries.key?(key.to_s) && !@lapsed_keys.include?(key.to_s)
      end

      def lapsed?(key)
        @lapsed_keys.include?(key.to_s)
      end

      def deleted?(key)
        @deleted_keys.include?(key.to_s)
      end

      # The recorded reason a key was lapsed, or nil if none recorded.
      def lapse_reason_for(key)
        @lapse_reasons[key.to_s]
      end

      def first_issue
        @history.first&.ob_issue_no
      end

      def last_issue
        @history.last&.ob_issue_no
      end

      def to_summary_hash
        {
          register_id: @register_id,
          at_ob_issue: @at_ob_issue,
          entry_count: entry_count,
          lapsed_count: @lapsed_keys.length,
          deleted_count: @deleted_keys.length,
          error_count: @error_count,
          history_length: @history.length,
        }
      end

      # Render this State as a JSON-ready Hash in the wire format
      # consumed by the Astro site's snapshot loader. The +slug+
      # argument is included because the wire format requires it
      # (the State itself only carries +register_id+).
      #
      # Pure: no I/O. Callers (e.g. SnapshotWriter) are responsible
      # for writing the result to disk.
      def to_snapshot(slug:)
        {
          'slug' => slug,
          'at_ob_issue' => @at_ob_issue,
          'entry_count' => entry_count,
          'lapsed_count' => @lapsed_keys.length,
          'deleted_count' => @deleted_keys.length,
          'error_count' => @error_count,
          'errors' => @errors,
          'active_entries' => @active_entries.values,
          'lapsed_keys' => @lapsed_keys.to_a.sort,
          'lapse_reasons' => @lapse_reasons,
          'deleted_keys' => @deleted_keys.to_a.sort,
          'history' => @history.map { |c| history_entry_to_hash(c) },
        }
      end

      private

      def history_entry_to_hash(change)
        {
          'type' => change.type,
          'ob_issue' => change.ob_issue_no,
          'identifier' => change.identifier.to_hash,
        }
      end
    end
  end
end
