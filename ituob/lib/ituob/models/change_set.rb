# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # ChangeSet class containing multiple changes and metadata
    class ChangeSet < Lutaml::Model::Serializable
      attribute :date_requested, :string
      attribute :date_active, :string
      attribute :ob_issue_no, :string
      attribute :reference, :string
      attribute :changes, Change, collection: true

      # YAML serialization mapping
      key_value do
        map 'date_requested', to: :date_requested
        map 'date_active', to: :date_active
        map 'ob_issue_no', to: :ob_issue_no
        map 'reference', to: :reference
        map 'changes', to: :changes
      end
    end
  end
end
