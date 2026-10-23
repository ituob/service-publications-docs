# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # LIR — "read from the last issue": the printed table repeats
      # entries unchanged from the previous edition, for the reader's
      # convenience. This is NOT a state change: the entry must exist
      # (a missing key is a data gap worth reporting), and the stored
      # row is refreshed from the printed table so the replayed state
      # tracks the bulletin verbatim. Reversible by a subsequent REP.
      class Lir < Base
        def self.validate!(builder, change, key, _row = nil)
          return if builder.entries.key?(key)

          raise StrategyError,
                "LIR conflict: key #{key.inspect} not present in register #{change.register_id}"
        end

        def self.apply_row(builder, change, key_field, key, row)
          refreshed = row.dup
          refreshed[key_field] = key
          builder.set_entry(key, refreshed)
        end

        # Identifier-only LIR (no keyable rows): presence was already
        # validated; the entry is unchanged by definition.
        def self.apply(builder, change, key_field, key)
          builder.entries[key]
        end
      end
    end
  end
end
