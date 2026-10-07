# frozen_string_literal: true


module Ituob
  module Models
    class M1400Entry < Entry
      DATASET_CODE = 'M1400_ICC'

      attribute :iso_code, :string
      attribute :country_or_area, MultilingualString
      attribute :company_name, :string
      attribute :address_line_1, :string
      attribute :address_line_2, :string
      attribute :address_line_3, :string
      attribute :carrier_code, :string
      attribute :contact, :string
      attribute :tel, :string
      attribute :fax, :string 
      attribute :email, :string, collection: true
    end
  end
end
