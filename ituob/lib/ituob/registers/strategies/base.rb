# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # Protocol all strategies implement.
      #
      # +apply(builder, change, key_field)+ mutates the builder's
      # +entries+ / +lapsed_keys+ / +deleted_keys+ according to the
      # change's action type.
      #
      # The +key+ for the affected row is computed by
      # +Base.resolve_key+; for direct identifiers it is the +code+
      # value, for query identifiers the builder performs the lookup.
      class Base
        # Does this strategy destroy or remove data? Default false.
        # Destructive strategies (SUP, LIR, DEL) override to return
        # true. Used by +ActionType#destructive?+ so the
        # classification lives with the strategy, not in ActionType.
        def self.destructive?
          false
        end

        # Resolve the key (string) that a change targets, given the
        # current builder state. For direct identifiers this is the
        # declared code. For query identifiers we search current
        # entries.
        def self.resolve_key(builder, change, key_field)
          if change.identifier.direct?
            change.identifier.code
          else
            builder.find_key_by_query(change.identifier, key_field)
          end
        end

        # Hook: raise when preconditions are not met.
        # Subclasses override to enforce "must exist" / "must not
        # exist" invariants.
        def self.validate!(builder, change, key); end

        # Hook: perform the mutation. Subclasses override.
        def self.apply(builder, change, key_field)
          raise NotImplementedError, "#{name}.apply not implemented"
        end

        # Common entry: validate then apply.
        def self.call(builder, change, key_field)
          key = resolve_key(builder, change, key_field)
          validate!(builder, change, key)
          apply(builder, change, key_field, key)
        end
      end
    end
  end
end
