# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # SUP — suppress an entry. Hard delete by default but records
      # the removal in +deleted_keys+ so the history audit trail
      # retains it. Optional +superseded_by.identifier.code+ for
      # redirects to a replacement entry.
      class Sup < Base
        def self.destructive?
          true
        end

        def self.validate!(builder, change, key)
          return if builder.entries.key?(key)

          raise StrategyError,
                "SUP conflict: key #{key.inspect} not present in register #{change.register_id}"
        end

        def self.apply(builder, change, key_field, key)
          builder.remove_entry(key)
          builder.mark_deleted(key)
          if change.superseded_by &&
             change.superseded_by['identifier'] &&
             change.superseded_by['identifier']['code']
            builder.record_supersession(key, change.superseded_by['identifier']['code'])
          end
        end
      end
    end
  end
end
