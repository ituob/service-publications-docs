# frozen_string_literal: true

require_relative 'entry'
require_relative 'e164cc_entry'

module Ituob
  module Models
    class E164CCAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, E164CCEntry, collection: true 
      attribute :notes, :string
      attribute :note, :string # i.e. note o p q n

      # def initialize(attributes = {})
      #   #@entry = E164CCEntry.new
      #   super
      # end
    end
  end
end
