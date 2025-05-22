# frozen_string_literal: true

require_relative 'x121dnic_entry'

module Ituob
  module Models
    class X121DNICAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, X121DNICEntry, collection: true 
      attribute :notes, :string

      # def initialize(attributes = {})
      #   #@entry = X121DNICEntry.new
      #   super
      # end
    end
  end
end
