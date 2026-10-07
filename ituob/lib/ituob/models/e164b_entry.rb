# frozen_string_literal: true


module Ituob
  module Models
    class E164BEntry < Entry
      DATASET_CODE = '1015-E.164B'

      attribute :country_or_area, MultilingualString
      attribute :country_code, :string
      attribute :mobile_telephone_numbers, MultilingualString
      attribute :remarks, :string

    end
  end
end
