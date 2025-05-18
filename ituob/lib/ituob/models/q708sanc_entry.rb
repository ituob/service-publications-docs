# frozen_string_literal: true

require_relative 'multilingual_string'

module Ituob
  module Models
    class Q708SANCEntry < Entry
      DATASET_CODE = 'Q708_SANC'

      attribute :code, :string
      attribute :area_or_network, MultilingualString
      attribute :note, MultilingualString
    end
  end
end
