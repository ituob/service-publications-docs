# frozen_string_literal: true

require_relative 'entry'
require_relative 'entry'

module Ituob
  module Models
    class M1400Action < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, M1400Entry, collection: true 
      attribute :notes, :string
      attribute :note, :string # i.e. note o p q n

      # def initialize(attributes = {})
      #   #@entry = M1400Entry.new
      #   super
      # end
    end
  end
end
