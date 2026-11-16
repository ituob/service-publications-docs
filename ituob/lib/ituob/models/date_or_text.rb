# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # A value the corpus stores as a calendar date, a timestamp or
    # free text, kept exactly as stored.
    #
    # Approved-recommendation dates, issue dates and telephone-service
    # communication dates mix all three (`2012-01-31T23:00:00Z`,
    # `2012-02-01`, `"2015"`). Typing them :date or :string would turn
    # a timestamp into a different calendar day or a different string,
    # so this type casts nothing: a Time stays a Time, a Date stays a
    # Date, a String stays a String.
    class DateOrText < Lutaml::Model::Type::Value
      def self.cast(value)
        value.is_a?(DateOrText) ? value.value : value
      end

      def self.serialize(value)
        value
      end
    end
  end
end
