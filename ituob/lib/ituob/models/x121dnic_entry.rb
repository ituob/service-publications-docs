# frozen_string_literal: true

require_relative 'multilingual_string'

module Ituob
  module Models
    class X121DNICEntry < Entry
      DATASET_CODE = 'F32_TDI'

      attribute :dnic_number, :string
      attribute :country_or_area, MultilingualString
      attribute :network_name, :string
      attribute :note, :string

    end
  end
end
