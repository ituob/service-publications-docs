# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # YAML mapping keys retain their scalar type: 1092 and '1092' are
    # different publications. Casting either to String would merge them.
    class AnnexPublicationId < Lutaml::Model::Type::Value
      def self.cast(value)
        value.is_a?(self) ? value.value : value
      end

      def self.serialize(value)
        value
      end
    end
  end
end
