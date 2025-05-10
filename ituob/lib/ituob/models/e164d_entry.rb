# frozen_string_literal: true

require_relative 'entry'
require_relative 'multilingual_string'

module Ituob
  module Models
    class E164DEntry < Entry
      DATASET_CODE = '1114-E.164D'

      attribute :country_code, :string
      attribute :country_area_or_service, MultilingualString
      attribute :note, MultilingualString
    end
  end
end
