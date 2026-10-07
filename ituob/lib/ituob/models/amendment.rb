# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    class Amendment < Lutaml::Model::Serializable
      attribute :_class, :string, polymorphic_class: true, default: -> { self.name }
      attribute :position_on, :date
      attribute :notes, :string, collection: true

      # Every amendment parser exposes an actions collection; guard it
      # once here instead of in each parser's initialize.
      def initialize(attributes = {})
        super
        @actions ||= []
        @notes ||= []
      end

      def notes
        @notes ||= []
        @notes
      end

      def notes=(value)
        @notes = Array(value)
      end

      # Printed action keywords shared by every amendment parser.
      ACTION_KEYWORDS = %w[ADD SUP REP LIR MOD DEL].freeze

      # The first printed action keyword appearing in +text+ (word
      # bounded), or nil.
      def self.action_keyword_in(text)
        ACTION_KEYWORDS.find { |kw| text.match?(/\b#{kw}\b/) }
      end
    end
  end
end
