# frozen_string_literal: true

require_relative 'dp_entry'

module Ituob
  module Models
    class DPAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, DPEntry, collection: true
      attribute :notes, :string

      def initialize(attributes = {})
        super
        @entries ||= []
      end
    end
  end
end
