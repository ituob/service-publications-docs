# frozen_string_literal: true


module Ituob
  module Models
    class E164ACNAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, E164ACNEntry, collection: true
      attribute :notes, :string
      # Printed heading words beyond the position and action ("Georgie").
      attribute :caption, :string

      def initialize(attributes = {})
        @entries = []
        super
      end
    end
  end
end
