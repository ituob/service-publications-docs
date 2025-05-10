# frozen_string_literal: true

require_relative 'entry'
require_relative 'e118_entry'

module Ituob
  module Models
    class E118Action < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entry, E118Entry

      def initialize(attributes = {})
        @entry = E118Entry.new
        super
      end
    end
  end
end
