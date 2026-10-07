# frozen_string_literal: true


module Ituob
  module Models
    class E218TRCCAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, E218TRCCEntry, collection: true 
      attribute :notes, :string

      # def initialize(attributes = {})
      #   #@entry = E218TRCCEntry.new
      #   super
      # end
    end
  end
end
