# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models

    class MultilingualString < Lutaml::Model::Serializable
      # Multilingual string class for handling multilingual data
      attribute :en, :string
      attribute :fr, :string
      attribute :es, :string
      attribute :zh, :string
      attribute :ru, :string
      attribute :ar, :string
    end

  end
end
