# frozen_string_literal: true

module Ituob
  module Models
    # A national numbering plan as printed across three sources:
    #
    #   NNP amendments        — "Country | Country Code (CC)" 2-column
    #                           listing of updated plans
    #   DP amendments         — the full 7-column plan row
    #   F.32 TDI amendments   — the same 7-column plan embedded for
    #                           context (currently kept as a note)
    #
    # One concept, one model. NNP fills country + code; DP fills all
    # seven printed columns.
    class NumberingPlanEntry < Entry
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
