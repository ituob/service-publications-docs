# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # LIR — Lapsed / Inactive Record. Soft-delete: the row stays in
      # +entries+ (history) but is excluded from the active view via
      # +lapsed_keys+. The +reason+ field carries the human-readable
      # explanation. Reversible by a subsequent REP.
      class Lir < Base
        def self.destructive?
          true
        end

        def self.validate!(builder, change, key)
          return if builder.entries.key?(key)

          raise StrategyError,
                "LIR conflict: key #{key.inspect} not present in register #{change.register_id}"
        end

        def self.apply(builder, change, key_field, key)
          builder.mark_lapsed(key, reason: change.reason)
        end
      end
    end
  end
end
