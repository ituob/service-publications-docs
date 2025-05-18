# frozen_string_literal: true

require_relative 'e118_entry'

module Ituob
  module Models
    class E118Action < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, E118Entry, collection: true 

      def initialize(attributes = {})
        @entries << E118Entry.new
        super
      end
    end
  end
end
