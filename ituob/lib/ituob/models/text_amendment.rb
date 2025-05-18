# frozen_string_literal: true

require_relative 'amendment'
require_relative 'text_entry'
require_relative 'text_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class TextAmendment < Amendment
      attribute :actions, TextAction, collection: true
      attribute :_class, :string, default: -> { self.name.split('::').last }
      attribute :dataset_code, :string
      attribute :text, :string

      key_value do
        map '_class', to: :_class, render_default: true
        map 'position_on', to: :position_on
        map 'actions', to: :actions
      end

      def initialize(attributes = {})
        super
        @actions ||= []
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new

        # Set the position_on if it exists
        amendment.position_on = position_on if position_on

        doc = Prosereflect::Parser.parse_document(hash)

        amendment.dataset_code = dataset_code
        amendment.text = Ituob::Helpers.dump_doc_verbose(doc).to_json

        amendment
      end

    end
  end
end
