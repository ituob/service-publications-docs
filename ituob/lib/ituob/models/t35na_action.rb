# frozen_string_literal: true

require_relative 't35na_entry'

module Ituob
  module Models
    class T35NAAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, T35NAEntry, collection: true 
      attribute :notes, :string
    end
  end
end
