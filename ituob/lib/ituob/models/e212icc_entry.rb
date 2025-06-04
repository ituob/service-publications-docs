# frozen_string_literal: true

require_relative 'multilingual_string'
require_relative 'entry'

module Ituob
  module Models
    class E212ICCEntry < Entry
      DATASET_CODE = 'E212_ICC'

      attribute :code, :string
      attribute :country_or_area, MultilingualString
      attribute :note, MultilingualString
    end
  end
end
