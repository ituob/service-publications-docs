# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # One publication annexed to an issue, with the position (date) of the
    # annexed list. On the wire the publication id is the key of the issue's
    # annexes.yaml mapping (see IssueAnnexes); here it is a field.
    class AnnexedPosition < Lutaml::Model::Serializable
      attribute :publication_id, :string
      attribute :position_on, DateOrText
      attribute :datasets, :hash
    end
  end
end
