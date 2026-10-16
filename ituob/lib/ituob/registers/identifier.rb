# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Registers
    # Immutable identifier for the row(s) targeted by a change.
    #
    # Two forms:
    #   * Direct: by +code+ (the register's key value as a string).
    #   * Query: by { field:, value:, operator: }.
    #
    # Reads only — strategies call `#matches?` to test against an
    # entry's fields.
    #
    # Serialized via +lutaml-model+ (no hand-rolled +to_h+). Use
    # +to_hash+ / +from_hash+ for the canonical wire shape.
    class Identifier < Lutaml::Model::Serializable
      include Comparable
      include Ituob::Support::HashField

      VALID_OPERATORS = %w[equals contains startsWith endsWith greaterThan lessThan in].freeze

      attribute :code, :string
      attribute :query, :hash

      key_value do
        map :code, to: :code
        map :query, to: :query
      end

      def initialize(code: nil, query: nil, **lutaml_options)
        super(lutaml_options)
        self.code = code&.to_s
        self.query = query ? query.transform_keys(&:to_s) : nil
        # Only validate+freeze when constructed directly (not by lutaml from_hash,
        # which sets attributes after initialize and validates separately).
        return unless code || query

        normalize_query!
        validate_exactly_one!
        freeze
      end

      def self.from_hash(hash)
        hash = hash.to_h if hash.is_a?(Hash)
        instance = super
        instance.normalize_query!
        instance.validate_exactly_one!
        instance.freeze
      end

      def direct? = !code.nil? && code != ''

      def normalize_query!
        return if query.nil? || query.empty?

        q = query.transform_keys(&:to_s)
        field = q['field'].to_s
        value = q['value']
        operator = (q['operator'] || 'equals').to_s
        raise ArgumentError, "invalid operator: #{operator}" unless VALID_OPERATORS.include?(operator)

        self.query = { 'field' => field, 'value' => value, 'operator' => operator }
      end

      def validate_exactly_one!
        code_present = !code.nil? && code != ''
        query_present = !query.nil? && !query.empty?
        return if code_present ^ query_present

        raise ArgumentError, 'exactly one of code or query is required'
      end

      def matches?(entry, key_field)
        return false if entry.nil?

        if direct?
          entry_value = lookup(entry, key_field)
          return entry_value.to_s == code
        end

        apply_query(entry)
      end

      def hash = to_hash.hash
      def eql?(other)
        other.is_a?(Identifier) && to_hash == other.to_hash
      end

      def <=>(other)
        return nil unless other.is_a?(Identifier)
        to_hash.inspect <=> other.to_hash.inspect
      end

      private

      def apply_query(entry)
        field_value = lookup(entry, query['field'])
        target = query['value']
        case query['operator']
        when 'equals' then field_value.to_s == target.to_s
        when 'contains' then field_value.to_s.include?(target.to_s)
        when 'startsWith' then field_value.to_s.start_with?(target.to_s)
        when 'endsWith' then field_value.to_s.end_with?(target.to_s)
        when 'greaterThan' then field_value.to_s > target.to_s
        when 'lessThan' then field_value.to_s < target.to_s
        when 'in' then Array(target).map(&:to_s).include?(field_value.to_s)
        else false
        end
      end
    end
  end
end
