# frozen_string_literal: true

require_relative 'multilingual_string'
require_relative 'entry'

module Ituob
  module Models
    class F32TDIEntry < Entry
      DATASET_CODE = 'F32_TDI'

      attribute :country_or_area, MultilingualString
      attribute :country_or_area_note, MultilingualString
      attribute :notes, MultilingualString
      attribute :network_roa, :string
      attribute :network_roa_note, :string
      attribute :network_code, :string
      attribute :network_code_note, MultilingualString
      attribute :telegraph_office_name, MultilingualString
      attribute :office_code, :string
      attribute :office_code_note, MultilingualString
      attribute :subarea, MultilingualString
    end
  end
end
