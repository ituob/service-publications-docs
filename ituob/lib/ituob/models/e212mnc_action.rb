# frozen_string_literal: true

require_relative 'entry'
require_relative 'e212mnc_entry'

module Ituob
  module Models
    class E212MNCAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, E212MNCEntry, collection: true 
      attribute :notes, :string
      attribute :note, :string # i.e. note o p q n

      # def initialize(attributes = {})
      #   #@entry = E212MNCEntry.new
      #   super
      # end
    end
  end
end
