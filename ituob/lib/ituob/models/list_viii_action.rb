# frozen_string_literal: true

module Ituob
  module Models
    # One change group of a List VIII amendment: the P-line position
    # ("P 43 COL 1-6"), action keyword, verbatim description, and the
    # stations affected.
    class ListVIIIAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :country, :string
      attribute :description, :string
      attribute :entries, ListVIIIStation, collection: true
    end
  end
end
