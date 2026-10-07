# frozen_string_literal: true


module Ituob
  module Models
    class Q708SANCAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, Q708SANCEntry, collection: true 
      attribute :notes, :string
      attribute :order, :string

      # def initialize(attributes = {})
      #   #@entry = Q708SANCEntry.new
      #   super
      # end
    end
  end
end
