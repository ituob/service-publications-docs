# frozen_string_literal: true


module Ituob
  module Models
    class E118Action < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      # Printed heading text ahead of the position/action marker, kept only when
      # it says more than the entry's own country cell.
      attribute :country, :string
      # Printed text after the action marker ("P 49 ADD Vodafone Group Services
      # Ltd, United Kingdom"), kept as printed.
      attribute :caption, :string
      attribute :entries, E118Entry, collection: true

      def initialize(attributes = {})
        super
        self.entries = []
      end
    end
  end
end
