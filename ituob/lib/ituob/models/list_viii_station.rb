# frozen_string_literal: true

module Ituob
  module Models
    # A List VIII (coast/monitoring stations) entry: the country line
    # ("RUS  Russian Federation"), the station row (name, postal
    # address, contact), the Part I index references, and its
    # centralizing office and measurement services.
    class ListVIIIStation < Entry
      DATASET_CODE = 'R_SP_LN.VIII'

      attribute :country, :string
      attribute :name, :string
      attribute :postal_address, :string
      attribute :contact, :string
      attribute :part_ii_reference, :string
      attribute :part_iii_reference, :string
      attribute :centralizing_office, ListVIIICentralizingOffice
      attribute :measurements, ListVIIIMeasurement, collection: true

      def initialize(attributes = {})
        super
        @measurements ||= []
      end
    end
  end
end
