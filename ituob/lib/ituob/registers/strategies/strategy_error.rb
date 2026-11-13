# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # Error raised by a strategy when preconditions are not met
      # (conflict, missing key, etc.).
      #
      # +key+ is the register key the failed check was about, when the
      # strategy knows it (nil otherwise, e.g. an unresolvable query).
      class StrategyError < StandardError
        attr_reader :key

        def initialize(message = nil, key: nil)
          super(message)
          @key = key
        end
      end
    end
  end
end
