# frozen_string_literal: true

module Ituob
  module Models
    # One measurement service of a List VIII monitoring station, as
    # printed in the Section A/B/C tables: station, coordinates,
    # hours, frequency ranges, then the section-specific measurement
    # columns (precision, maximum/minimum values, ...) kept verbatim
    # in +details+.
    class ListVIIIMeasurement < Lutaml::Model::Serializable
      attribute :section, :string
      attribute :measurement_type, :string
      attribute :coordinates, :string
      attribute :hours_of_service, :string
      attribute :frequency_ranges, :string
      attribute :details, :string
      attribute :remarks, :string
    end
  end
end
