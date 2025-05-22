# frozen_string_literal: true

require_relative 'multilingual_string'

module Ituob
  module Models
    class F400Entry < Entry
      DATASET_CODE = 'F400_ADMD'

      attribute :country_or_area, MultilingualString
      attribute :admd_name, :string
      attribute :not_operational_yet, :boolean
      attribute :country_code, :string
      attribute :for_test_purposes, :boolean
      attribute :mt, :string
      attribute :ipm, :string
      attribute :other, :string
      attribute :helpdesk, :hash
      attribute :autoanswer, :hash
      attribute :contact_address, :hash
      attribute :note, :string

    end
  end
end
