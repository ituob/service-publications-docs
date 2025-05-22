# frozen_string_literal: true

require_relative 'multilingual_string'
require_relative 'entry'

module Ituob
  module Models
    class E212MNCEntry < Entry
      DATASET_CODE = 'E212_MNC'

      attribute :mcc_mnc_codes, :string
      attribute :country_or_area, MultilingualString
      attribute :networks, :string
      attribute :note, MultilingualString
      attribute :former_name, :string
    end
  end
end
