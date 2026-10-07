# frozen_string_literal: true


module Ituob
  module Models
    class Q708ISPCEntry < Entry
      DATASET_CODE = 'Q708_ISPC'

      attribute :ipsc, :string
      attribute :country, MultilingualString
      attribute :dec, :string
      attribute :signal_point_name, :string
      attribute :signal_point_operator, :string
    end
  end
end
