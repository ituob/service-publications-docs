# frozen_string_literal: true

# Per-action-type strategies. Each class implements the protocol
# defined by +Base+:
#
#   apply(state_mutable, change, key_field)   → void
#
# A strategy mutates a +StateBuilder+ (the working state used by the
# Replay engine) and returns nothing. New action types = new strategy
# class — no edit to existing classes (OCP).
module Ituob
  module Registers
    module Strategies
      autoload :Base, 'ituob/registers/strategies/base'
      autoload :StrategyError, 'ituob/registers/strategies/strategy_error'
      autoload :Add, 'ituob/registers/strategies/add'
      autoload :Sup, 'ituob/registers/strategies/sup'
      autoload :Rep, 'ituob/registers/strategies/rep'
      autoload :Lir, 'ituob/registers/strategies/lir'
      autoload :Mod, 'ituob/registers/strategies/mod'
      autoload :Del, 'ituob/registers/strategies/del'
      autoload :Seed, 'ituob/registers/strategies/seed'
      autoload :Resolver, 'ituob/registers/strategies/resolver'
    end
  end
end
