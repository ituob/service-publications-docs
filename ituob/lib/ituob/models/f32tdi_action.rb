# frozen_string_literal: true

require_relative 'entry'
require_relative 'f32tdi_entry'

module Ituob
  module Models
    class F32TDIAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :entries, F32TDIEntry, collection: true 
      attribute :notes, :string

      # def initialize(attributes = {})
      #   #@entry = F32TDIEntry.new
      #   super
      # end
    end
  end
end
