# frozen_string_literal: true

require_relative 'f400_entry'

module Ituob
  module Models
    class F400Action < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, F400Entry, collection: true 
      attribute :notes, :string

      # def initialize(attributes = {})
      #   #@entry = F400Entry.new
      #   super
      # end
    end
  end
end
