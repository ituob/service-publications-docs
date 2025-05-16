# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    class Amendment < Lutaml::Model::Serializable
      attribute :_class, :string, polymorphic_class: true, default: -> { self.name }
      attribute :position_on, :date
    end

  end
end
