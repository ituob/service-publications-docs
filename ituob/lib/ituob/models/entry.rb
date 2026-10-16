# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # Base class for all dataset entries
    class Entry < Lutaml::Model::Serializable
      attribute :_class, :string, polymorphic_class: true, default: -> { self.name }
    end
  end
end
