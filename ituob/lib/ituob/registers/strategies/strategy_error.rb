# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # Error raised by a strategy when preconditions are not met
      # (conflict, missing key, etc.).
      class StrategyError < StandardError; end
    end
  end
end
