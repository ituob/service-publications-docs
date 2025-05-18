# frozen_string_literal: true

require_relative 'multilingual_string'

module Ituob
  module Models
    class E164ACNEntry < Entry
      DATASET_CODE = 'E164_ACN'

      attribute :country_or_area, MultilingualString
      attribute :country_code, :string
      attribute :mobile_telephone_numbers, MultilingualString
    end
  end
end
