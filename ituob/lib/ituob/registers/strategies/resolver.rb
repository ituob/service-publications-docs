# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # Dispatches a Change to its corresponding strategy class.
      # OCP: registering a new action type means adding to
      # +ActionType.strategy_class_name+ and creating a new strategy
      # class — this file never changes for new types.
      class Resolver
        @cache = {}

        class << self
          # Resolve the strategy class for an action type (string or
          # ActionType). Memoized per action type.
          def strategy_for(action_type)
            key = ActionType.coerce(action_type).value
            @cache[key] ||= resolve_strategy_class(key)
          end

          # Apply +change+ to +builder+ using the appropriate strategy.
          def apply(builder, change, key_field)
            strategy = strategy_for(change.type)
            strategy.call(builder, change, key_field)
          end

          private

          def resolve_strategy_class(action_value)
            at = ActionType.new(action_value)
            at.strategy_class_name.split('::').reduce(Object) do |mod, name|
              mod.const_get(name)
            end
          end
        end
      end
    end
  end
end
