# frozen_string_literal: true

require 'date'

module Ituob
  # ITU Operational Bulletin date formatting.
  #
  # The OB uses a canonical date format with Roman numerals for the month:
  #
  #   15.V.2016   →  15 May 2016
  #   1.IX.2010   →  1 September 2010
  #
  # This format appears in every printed OB edition and on the authoritative
  # ITU website. All renderers that emit dates for human consumption must
  # use this format for parity.
  module ObDate
    ROMAN_MONTHS = %w[I II III IV V VI VII VIII IX X XI XII].freeze
    MONTH_NAMES_EN = %w[January February March April May June July
                        August September October November December].freeze

    module_function

    # Format a Date, Time, or ISO 8601 string in the canonical OB style.
    #
    #   ObDate.format(Date.new(2016, 5, 15))   # => "15.V.2016"
    #   ObDate.format("2016-05-15")            # => "15.V.2016"
    #
    # Returns +nil+ for +nil+ input, or an empty string for unparseable input.
    def format(value)
      d = coerce(value)
      return nil if d.nil?

      "#{d.day}.#{ROMAN_MONTHS.fetch(d.month - 1)}.#{d.year}"
    end

    # Format with the month spelled out (English long form).
    #
    #   ObDate.format_long(Date.new(2016, 5, 15))  # => "15 May 2016"
    #
    # Use only for non-OB contexts (e.g. human-readable metadata).
    def format_long(value)
      d = coerce(value)
      return nil if d.nil?

      "#{d.day} #{MONTH_NAMES_EN.fetch(d.month - 1)} #{d.year}"
    end

    # Parse an OB-formatted date string (+15.V.2016+) back into a Date.
    #
    # Returns +nil+ if the input does not match the expected pattern.
    def parse(text)
      return nil if text.nil? || text.to_s.strip.empty?

      m = text.to_s.strip.match(/\A(\d{1,2})\.([IVX]+)\.(\d{4})\z/)
      return nil unless m

      day = m[1].to_i
      month_idx = ROMAN_MONTHS.index(m[2])
      return nil if month_idx.nil?

      year = m[3].to_i
      Date.new(year, month_idx + 1, day)
    rescue Date::Error
      nil
    end

    def coerce(value)
      return nil if value.nil?

      case value
      when Date   then value
      when Time   then value.to_date
      when DateTime then value.to_date
      when String then parse_iso(value) || parse(value)
      else nil
      end
    end

    def parse_iso(text)
      return nil if text.to_s.strip.empty?

      Date.iso8601(text.to_s)
    rescue Date::Error
      nil
    end

    private_class_method :coerce, :parse_iso
  end
end
