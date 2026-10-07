# frozen_string_literal: true

module Ituob
  module Models
    class X121DNICEntry < Entry
      DATASET_CODE = 'X121_DNIC'

      attribute :dnic_number, :string
      attribute :country_or_area, MultilingualString
      attribute :network_name, :string
      attribute :note, :string
    end
  end
end
