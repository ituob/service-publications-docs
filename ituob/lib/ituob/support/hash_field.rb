# frozen_string_literal: true

module Ituob
  module Support
    # Stateless utility for normalized Hash field access.
    #
    # Register data can come from YAML (string keys) or Ruby literals
    # (symbol keys). This module provides a single pair of helpers
    # that always read with string-wins-over-symbol precedence and
    # always write with the canonical string form.
    #
    # Used by +Registers::Identifier#matches?+ and the per-action
    # strategies so the lookup policy lives in one place.
    module HashField
      module_function

      # Read +hash[key]+. Tries the string form first, then the
      # symbol form, then returns nil. Returns nil for non-hash
      # input. Mirrors the wire-format convention of string keys.
      def lookup(hash, key)
        return nil unless hash.is_a?(Hash)

        string_key = key.to_s
        return hash[string_key] if hash.key?(string_key)

        symbol_key = key.to_sym
        return hash[symbol_key] if hash.key?(symbol_key)

        nil
      end

      # Write +hash[key] = value+. Always uses the string form of
      # +key+ so the canonical representation is consistent across
      # writers.
      def set(hash, key, value)
        hash[key.to_s] = value
      end

      # Does +hash+ contain +key+ (in either string or symbol form)?
      def contains?(hash, key)
        return false unless hash.is_a?(Hash)

        hash.key?(key.to_s) || hash.key?(key.to_sym)
      end
    end
  end
end
