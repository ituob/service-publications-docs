# frozen_string_literal: true

require_relative 'multilingual_string'
require_relative 'entry'

module Ituob
  module Models
    class E218TRCCEntry < Entry
      DATASET_CODE = 'E218_TRCC'

      attribute :tmcc_code, :string
      attribute :country_or_area, MultilingualString
      attribute :reserved, :boolean
      attribute :note, MultilingualString
    end
  end
end
