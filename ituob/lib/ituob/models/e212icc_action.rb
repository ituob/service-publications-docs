# frozen_string_literal: true

require_relative 'e212icc_entry'

module Ituob
  module Models
    class E212ICCAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, E212ICCEntry, collection: true 
      attribute :order, :string
      attribute :notes, :string
      attribute :note, :string # i.e. note o p q n

      # def initialize(attributes = {})
      #   #@entry = E212ICCEntry.new
      #   super
      # end
    end
  end
end
