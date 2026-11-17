# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # A mapping for an amendment or a plain list of rows for a seed batch.
    class HashOrList < Lutaml::Model::Type::Hash
      # lutaml-model 0.8 casts setter values element by element and wraps
      # mappings in custom type instances. This singular type owns the
      # entire value, just as it does during mapped deserialization.
      module AttributeCasting
        def cast_value(value, register)
          type(register).cast(value)
        end
      end

      def self.configure_attribute(attribute)
        attribute.extend(AttributeCasting)
      end

      def self.cast(value)
        case value
        when ::Array then value
        when HashOrList then value.value
        else super
        end
      end

      def self.serialize(value)
        value.is_a?(::Array) ? value : super
      end
    end
  end
end
