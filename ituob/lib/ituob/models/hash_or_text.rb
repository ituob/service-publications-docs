# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # A mapping (for example a ProseMirror document) or, in a few
    # corpus files, a plain string that names a source asset
    # (`contents: general/misc_comms.adoc`). Behaves as :hash for a
    # mapping and keeps a string as the string it was stored as.
    class HashOrText < Lutaml::Model::Type::Hash
      # lutaml-model's Attribute#cast_element wraps a Hash in the type
      # instance for every type but exactly Type::Hash (`hash_type?` is
      # `type == Type::Hash`). Declaring ourselves equal to Type::Hash makes
      # a mapping load as the plain Hash, as `:hash` does, while a string
      # still passes through `cast` unchanged.
      #
      # The equality is deliberately one-way: `Type::Hash == HashOrText` and
      # `!=` stay false/true, and eql?/hash are untouched. Overriding `.new`
      # to return the Hash instead was tried and rejected: lutaml-model's
      # `wrap_in_type_if_needed` builds `resolved_type.new(value)` on
      # serialization and calls `to_yaml`/`to_json` on it, so a bare Hash
      # serialized as an embedded string.
      def self.==(other)
        other.equal?(Lutaml::Model::Type::Hash) || super
      end

      def self.cast(value)
        case value
        when ::String then value
        when HashOrText then value.value
        else super
        end
      end

      def self.serialize(value)
        value.is_a?(::String) ? value : super
      end
    end
  end
end
