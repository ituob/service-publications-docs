# frozen_string_literal: true

require_relative 'multilingual_string'

module Ituob
  module Models
    class DPEntry < Entry
      DATASET_CODE = 'DP'

      attribute :country_or_area, MultilingualString
      attribute :country_code, :string
      attribute :international_prefix, :string
      attribute :national_prefix, :string
      attribute :national_sig_number, :string
      attribute :utc_dst, :string
      attribute :note, MultilingualString
    end
  end
end
