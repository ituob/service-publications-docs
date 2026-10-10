# frozen_string_literal: true

module Ituob
  module Models
    # One change group of a DP (national numbering plan) amendment:
    # the P-line position ("P 4"), the printed country, the action
    # keyword (LIR) and the full 7-column plan row as the entry.
    class DPAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :country, :string
      attribute :description, :string
      attribute :entries, DPEntry, collection: true
      attribute :notes, :string
    end
  end
end
