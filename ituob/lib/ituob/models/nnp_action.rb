# frozen_string_literal: true

module Ituob
  module Models
    # One change group of an NNP (National Numbering Plans) amendment.
    # NNP issues print an intro ("From 1.V.2017 the following
    # countries/geographical areas have updated their national
    # numbering plans...") plus a 2-column country/code table; the
    # whole issue is one listing action.
    class NNPAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :description, :string
      attribute :entries, NumberingPlanEntry, collection: true
    end
  end
end
