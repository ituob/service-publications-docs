# frozen_string_literal: true

require_relative 'e164acn_entry'

module Ituob
  module Models
    class E164ACNAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, E164ACNEntry, collection: true
      attribute :notes, :string

      def initialize(attributes = {})
        @entries = []
        super
      end
    end
  end
end
