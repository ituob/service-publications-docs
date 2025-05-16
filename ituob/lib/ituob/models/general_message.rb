# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    class GeneralMessage < Lutaml::Model::Serializable
      attribute :type, :string
      # attribute :contents, :hash
    end
  end
end
