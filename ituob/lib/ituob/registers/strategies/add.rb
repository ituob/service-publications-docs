# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # ADD — insert a new entry. The printed bulletin is the
      # authority: re-publications of an existing key update the stored
      # row (verbatim reprints are no-ops). A conflict is raised only
      # when the ADD carries no row content to apply.
      class Add < Base
        def self.validate!(builder, change, key, row = nil)
          return unless builder.entries.key?(key)
          return unless row.nil?

          raise StrategyError,
                "ADD conflict: key #{key.inspect} already exists in register #{change.register_id}"
        end

        def self.apply_row(builder, change, key_field, key, row, _fallbacks = [])
          entry = row.dup
          entry[key_field] = key
          builder.set_entry(key, entry)
          builder.clear_lapsed(key)
          builder.clear_deleted(key)
        end

        def self.apply(builder, change, key_field, key, _fallbacks = [])
          row = change.data && change.data.is_a?(Hash) ? change.data.dup : {}
          row[key_field] = key
          builder.set_entry(key, row)
          builder.clear_lapsed(key)
          builder.clear_deleted(key)
        end

      end
    end
  end
end
