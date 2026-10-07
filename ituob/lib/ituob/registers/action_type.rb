# frozen_string_literal: true

module Ituob
  module Registers
    # Immutable value object representing one OB action type. Wraps the
    # raw string with type-safe semantics and metadata.
    class ActionType
      include Comparable

      VALID_TYPES = %w[ADD SUP REP LIR MOD DEL SEED].freeze

      attr_reader :value

      def initialize(value)
        raise ArgumentError, "invalid action type: #{value.inspect}" unless VALID_TYPES.include?(value.to_s.upcase)

        @value = value.to_s.upcase
        freeze
      end

      def self.coerce(value)
        return value if value.is_a?(ActionType)
        new(value)
      end

      def <=>(other)
        value <=> ActionType.coerce(other).value
      end

      def to_s = value
      def to_sym = value.to_sym

      def hash = value.hash
      def eql?(other) = other.is_a?(ActionType) && other.value == value

      # Strategy class name resolved by convention from the action value.
      #
      # ADD → Strategies::Add, LIR → Strategies::Lir, SEED →
      # Strategies::Seed. +capitalize+ on the upcased value yields the
      # class name suffix. Registering a new action type requires only:
      #   1. Append the value to +VALID_TYPES+.
      #   2. Create +Strategies::Foo+ with the matching capitalized name.
      # No edit to this file is required.
      def strategy_class_name
        "Ituob::Registers::Strategies::#{value.capitalize}"
      end

      # Resolve and return the strategy class itself. Used by
      # +destructive?+ and any caller that needs to introspect the
      # strategy.
      def strategy_class
        strategy_class_name.split('::').reduce(Object) do |mod, name|
          mod.const_get(name)
        end
      end

      # Whether this action destroys or removes data. Delegates to the
      # strategy class so new destructive action types declare their
      # destructiveness on the strategy, not here.
      def destructive?
        strategy_class.destructive?
      end

      # Auto-generate one predicate per valid action type. After TODO
      # 39 (convention-based strategy resolution), adding a new type
      # requires only VALID_TYPES + a Strategies::Foo class — the
      # predicate is auto-created here.
      VALID_TYPES.each do |type|
        define_method("#{type.downcase}?") { value == type }
      end
    end
  end
end
