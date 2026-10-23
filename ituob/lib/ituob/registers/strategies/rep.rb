# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # REP — wholesale replacement of an existing entry. Identifier
      # key MUST exist; the new row fully replaces the old one and
      # the lapsed flag is cleared.
      class Rep < Base
        extend Ituob::Support::HashField

        def self.validate!(builder, change, key, _row = nil)
          return if builder.entries.key?(key)

          raise StrategyError,
                "REP conflict: key #{key.inspect} not present in register #{change.register_id}"
        end

        def self.apply_row(builder, change, key_field, key, row, _fallbacks = [])
          entry = row.dup
          entry[key_field] = key
          builder.set_entry(key, entry)
          builder.clear_lapsed(key)
        end

        def self.apply(builder, change, key_field, key, _fallbacks = [])
          row = change.data && change.data.is_a?(Hash) ? change.data.dup : {}
          row[key_field] = key
          builder.set_entry(key, row)
          builder.clear_lapsed(key)
        end
      end
    end
  end
end
