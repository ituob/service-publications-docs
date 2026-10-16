# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # REP — wholesale replacement of an existing entry. Identifier
      # key MUST exist; the new row fully replaces the old one and
      # the lapsed flag is cleared.
      class Rep < Base
        extend Ituob::Support::HashField

        def self.validate!(builder, change, key)
          return if builder.entries.key?(key)

          raise StrategyError,
                "REP conflict: key #{key.inspect} not present in register #{change.register_id}"
        end

        def self.apply(builder, change, key_field, key)
          row = change.data && change.data.is_a?(Hash) ? change.data.dup : {}
          set(row, key_field, key)
          builder.set_entry(key, row)
          builder.clear_lapsed(key)
        end
      end
    end
  end
end
