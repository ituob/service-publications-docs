# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # LIR — "read from the last issue": the printed table repeats
      # entries unchanged from the previous edition, for the reader's
      # convenience. This is NOT a membership change: the printed row
      # is applied as-is, so a repetition of an entry the state does
      # not yet have inserts it (the bulletin asserts it exists);
      # an identifier-only repetition of an unknown key is a data gap
      # worth reporting. Reversible by a subsequent REP.
      class Lir < Base
        def self.validate!(builder, change, key, row = nil)
          return if builder.entries.key?(key) || row

          raise StrategyError,
                "LIR conflict: key #{key.inspect} not present in register #{change.register_id}"
        end

        def self.apply_row(builder, change, key_field, key, row, _fallbacks = [])
          refreshed = row.dup
          refreshed[key_field] = key
          builder.set_entry(key, refreshed)
        end

        # Identifier-only LIR (no keyable rows): presence was already
        # validated; the entry is unchanged by definition.
        def self.apply(builder, change, key_field, key, _fallbacks = [])
          builder.entries[key]
        end
      end
    end
  end
end
