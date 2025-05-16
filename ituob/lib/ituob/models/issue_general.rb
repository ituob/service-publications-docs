# frozen_string_literal: true

require 'lutaml/model'
require_relative 'multilingual_string'
require_relative 'general_message'

module Ituob
  module Models
    class IssueGeneral < Lutaml::Model::Serializable
      attribute :messages, GeneralMessage, collection: true, polymorphic: true

    end
  end
end
