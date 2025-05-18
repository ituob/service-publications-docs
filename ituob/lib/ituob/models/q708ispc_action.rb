# frozen_string_literal: true

require_relative 'entry'
require_relative 'q708ispc_entry'

module Ituob
  module Models
    class Q708ISPCAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, Q708ISPCEntry, collection: true 
      attribute :notes, :string

      # def initialize(attributes = {})
      #   #@entry = Q708ISPCEntry.new
      #   super
      # end
    end
  end
end
