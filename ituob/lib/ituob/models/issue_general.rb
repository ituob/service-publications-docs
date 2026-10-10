# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    class IssueGeneral < Lutaml::Model::Serializable
      attribute :messages, GeneralMessage, collection: true, polymorphic: true

    end
  end
end
