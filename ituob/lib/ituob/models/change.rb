# frozen_string_literal: true

require 'lutaml/model'
require_relative 'entry'

module Ituob
  module Models

    # Change class representing a change to a dataset entry
    class Change < Lutaml::Model::Serializable
      # Change types
      ADD = 'ADD'
      REP = 'REP' # Replace
      SUP = 'SUP' # Suppress/Delete

      attribute :type, :string, values: [ADD, REP, SUP]
      attribute :identifier, :string
      attribute :data, Entry

      # YAML serialization mapping
      key_value do
        map 'type', to: :type
        map 'identifier', to: :identifier
        map 'data', to: :data
      end
    end

  end
end
