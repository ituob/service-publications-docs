# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # ADD — insert a new entry. The key MUST NOT already exist,
      # unless the printed row is identical to the stored one (the
      # bulletin re-publishing an entry verbatim), which is a no-op.
      class Add < Base
        def self.validate!(builder, change, key, row = nil)
          return unless builder.entries.key?(key)
          return if row && rows_equal?(builder.entries[key], row, key)

          raise StrategyError,
                "ADD conflict: key #{key.inspect} already exists in register #{change.register_id}"
        end

        def self.apply_row(builder, change, key_field, key, row)
          entry = row.dup
          entry[key_field] = key
          builder.set_entry(key, entry)
          builder.clear_lapsed(key)
          builder.clear_deleted(key)
        end

        def self.apply(builder, change, key_field, key)
          row = change.data && change.data.is_a?(Hash) ? change.data.dup : {}
          row[key_field] = key
          builder.set_entry(key, row)
          builder.clear_lapsed(key)
          builder.clear_deleted(key)
        end

        def self.rows_equal?(stored, printed, key_field)
          a = stored.reject { |k, _| k.to_s == key_field.to_s }
          b = printed.reject { |k, _| k.to_s == key_field.to_s }
          a.map { |k, v| [k.to_s, v.is_a?(Hash) ? v : v.to_s] }.sort ==
            b.map { |k, v| [k.to_s, v.is_a?(Hash) ? v : v.to_s] }.sort
        end
      end
    end
  end
end
