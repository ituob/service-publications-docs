# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # ADD — insert a new entry. Identifier key MUST NOT already
      # exist in the active or lapsed set.
      class Add < Base
        extend Ituob::Support::HashField

        def self.validate!(builder, change, key)
          return unless builder.entries.key?(key)

          raise StrategyError,
                "ADD conflict: key #{key.inspect} already exists in register #{change.register_id}"
        end

        def self.apply(builder, change, key_field, key)
          row = change.data && change.data.is_a?(Hash) ? change.data.dup : {}
          set(row, key_field, key)
          builder.set_entry(key, row)
          builder.clear_lapsed(key)
          builder.clear_deleted(key)
        end
      end
    end
  end
end
