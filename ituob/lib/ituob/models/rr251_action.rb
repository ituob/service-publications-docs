# frozen_string_literal: true

require_relative 'rr251_entry'

module Ituob
  module Models
    class RR251Action < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, RR251Entry, collection: true 
      attribute :notes, :string

      # def initialize(attributes = {})
      #   #@entry = RR251Entry.new
      #   super
      # end
    end
  end
end
