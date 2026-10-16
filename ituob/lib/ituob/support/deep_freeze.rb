# frozen_string_literal: true

module Ituob
  module Support
    # Stateless utility for recursively freezing Hash / Array / leaves.
    #
    # Used by immutable value objects (+Registers::Change+,
    # +Registers::State+) so a single deep-freeze policy lives in one
    # place rather than being re-implemented per class.
    module DeepFreeze
      module_function

      # Recursively freeze +value+:
      # * Hash — freeze every value, then the hash itself.
      # * Array — freeze every element, then the array itself.
      # * Other — freeze if it responds to +freeze+.
      #
      # Returns the (now-frozen) input so callers can write
      # +@data = DeepFreeze.deep_freeze(data)+.
      def deep_freeze(value)
        case value
        when Hash
          value.each_value { |v| deep_freeze(v) }
          value.freeze
        when Array
          value.each { |v| deep_freeze(v) }
          value.freeze
        else
          value&.freeze
        end
      end
    end
  end
end
