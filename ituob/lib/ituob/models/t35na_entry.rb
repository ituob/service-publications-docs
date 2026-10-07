# frozen_string_literal: true


module Ituob
  module Models
    class T35NAEntry < Entry
      DATASET_CODE = 'E164_CC'

      attribute :country, :string
      attribute :administration_name, :string
      attribute :manufactures_htv, :string
      attribute :last_updated, :string
      attribute :assignment_authority, T35AssignmentAuthority, collection: true
      attribute :note, :string
    end
  end
end
