# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # A mapping (for example a ProseMirror document) or, in a few
    # corpus files, a plain string that names a source asset
    # (`contents: general/misc_comms.adoc`). Behaves as :hash for a
    # mapping and keeps a string as the string it was stored as.
    class HashOrText < Lutaml::Model::Type::Hash
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
