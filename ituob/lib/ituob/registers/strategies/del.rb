# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # DEL — hard delete. Irreversible. Removes from +entries+ and
      # records in +deleted_keys+ for audit. Distinct from SUP (which
      # may carry +superseded_by+ redirect). DEL is for compliance /
      # privacy removals.
      class Del < Base
        def self.destructive?
          true
        end

        def self.validate!(builder, change, key)
          return if builder.entries.key?(key)

          raise StrategyError,
                "DEL conflict: key #{key.inspect} not present in register #{change.register_id}"
        end

        def self.apply(builder, change, key_field, key)
          builder.remove_entry(key)
          builder.mark_deleted(key)
          builder.clear_lapsed(key)
        end
      end
    end
  end
end
