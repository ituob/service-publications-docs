# frozen_string_literal: true

require_relative 'amendment'
require_relative 'f32tdi_entry'
require_relative 'f32tdi_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class F32TDIAmendment < Amendment
      attribute :actions, F32TDIAction, collection: true
      attribute :notes, :string
      attribute :_class, :string, default: -> { self.name.split('::').last }

      key_value do
        map '_class', to: :_class, render_default: true
        map 'position_on', to: :position_on
        map 'actions', to: :actions
      end

      def initialize(attributes = {})
        super
        @actions ||= []
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new

        # Set the position_on if it exists
        amendment.position_on = position_on if position_on

        doc = Prosereflect::Parser.parse_document(hash)

        parse_state = {
          elem: "para", # or "table"
          page: nil,
          country: nil,
          action_type: nil,
        }

        @action = F32TDIAction.new
        @action.entries = []
        amendment.notes = []

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0]

          if first_elem.is_a?(String) && (first_elem.match(/^__/) || first_elem.match(/^----/))
            parse_state[:elem] = 'notes'
          elsif parse_state[:elem] == 'notes'
            amendment.notes << c
          elsif first_elem.is_a?(String)
            str = Ituob::Helpers.replace_legacy_space(first_elem)

            if parse_state[:elem] == 'table'
              # reinitialize action
              if @action
                amendment.actions << @action
                @action = F32TDIAction.new
                @action.entries = []
              end
              if str.match(/^P /)
                segs = Ituob::Helpers.split_str(str)
                @action.position = segs[0..1].join(" ")
                # @action.country = segs[2]
              elsif str.match(/^COL /)
                segs = Ituob::Helpers.split_str(str)
                @action.position += " " + segs[0..1].join(" ")
                @action.action_type = segs[-1]
              end
            end

            parse_state[:elem] = 'para'
          elsif first_elem.is_a?(Array) # table
            parse_state[:elem] = 'table'

            entry_rows = []
            c.each_with_index do |tc, tci|
              if tc.length < 3
                @action.notes = tc[0]
              elsif tc.all?{|x| x[0].strip.length == 0}
                # discard
              elsif tc[0][0].strip.match?(/^Country/)
                # header - discard
              elsif tc[0][0].strip.match?(/^1$/)
                # numbers header, discard
              elsif tc.length == 5 && [3,2].include?(tci)
                # semi header row, i guess
                @network_roa = tc[1][0].strip if tc[1][0].strip.length > 1
                @network_code = tc[2][0].strip if tc[2][0].strip.length > 1
                entry_rows << tc.map{|x| Ituob::Helpers.replace_legacy_space(x[0]).strip }
              elsif tc.count == 5
                entry_rows << tc.map{|x| Ituob::Helpers.replace_legacy_space(x[0]).strip }
              end
            end

            countries = c.map{|x| x[0]}.flatten.select{|x|x.length > 1 && x != "1" && !x.match(/^Country/)}.uniq
            country_or_area = MultilingualString.new( fr: countries[0], en: countries[1], es: countries[2] )

            network = entry_rows.map{|x|x[1]}.flatten.select{|x|x.length > 0}.join(" ")

            # Parse the telegraph offices and office codes from the table structure
            # In F32_TDI amendments, telegraph offices and office codes are stored as multiple paragraphs
            # within cells in the table structure

            # Find the row that contains the telegraph offices and office codes
            # This is typically the row with country information
            telegraph_offices_row = nil

            # Look for the row with country information by checking the first column
            c.each do |tc|
              if tc.is_a?(Array) && tc.length >= 5
                cell0 = tc[0]
                if cell0.is_a?(Array) && cell0.length > 0
                  # Check if this cell contains country information by joining all paragraphs
                  content = cell0.join(" ")
                  # Look for any country name - this is a generic approach that will work for any country
                  if content.length > 0 && !content.match?(/^Country/) && !content.match?(/^1$/)
                    telegraph_offices_row = tc
                    break
                  end
                end
              end
            end

            if telegraph_offices_row
              # Extract telegraph offices and office codes from the row
              telegraph_offices = []
              office_codes = []

              # Extract telegraph offices from column 4 (index 3)
              if telegraph_offices_row[3].is_a?(Array)
                # Each paragraph is a separate telegraph office
                telegraph_offices_row[3].each do |office|
                  if office.is_a?(String) && office.strip.length > 0 &&
                     office.strip != "4" && !office.strip.match?(/^Name of/)
                    telegraph_offices << office.strip
                  end
                end
              end

              # Extract office codes from column 5 (index 4)
              if telegraph_offices_row[4].is_a?(Array)
                # Each paragraph is a separate office code
                telegraph_offices_row[4].each do |code|
                  if code.is_a?(String) && code.strip.length > 0 &&
                     code.strip != "5" && !code.strip.match?(/^Office code/)
                    office_codes << code.strip
                  end
                end
              end

              # Create entries for each telegraph office and office code pair
              if telegraph_offices.length > 0 && office_codes.length > 0
                # Make sure we have the same number of offices and codes
                if telegraph_offices.length == office_codes.length
                  telegraph_offices.each_with_index do |office, index|
                    e = F32TDIEntry.new

                    e.country_or_area = country_or_area # MultilingualString
                    e.network_roa = @network_roa  # :string
                    e.network_code = @network_code  # :string
                    e.office_code = office_codes[index]  # :string
                    e.subarea = MultilingualString.new(en: office)  # MultilingualString

                    @action.entries << e
                  end
                else
                  puts "WARNING: Mismatch between number of telegraph offices (#{telegraph_offices.length}) and office codes (#{office_codes.length})"
                  # Try to create as many entries as possible
                  min_length = [telegraph_offices.length, office_codes.length].min
                  min_length.times do |index|
                    e = F32TDIEntry.new

                    e.country_or_area = country_or_area # MultilingualString
                    e.network_roa = @network_roa  # :string
                    e.network_code = @network_code  # :string
                    e.office_code = office_codes[index]  # :string
                    e.subarea = MultilingualString.new(en: telegraph_offices[index])  # MultilingualString

                    @action.entries << e
                  end
                end
              else
                # Fallback to the original implementation if we couldn't find telegraph offices and office codes
                entry_rows.each do |r|
                  e = F32TDIEntry.new

                  e.country_or_area = country_or_area # MultilingualString
                  e.network_roa = @network_roa  # :string
                  e.network_code = @network_code  # :string
                  e.office_code = r[4]  # :string
                  e.subarea = MultilingualString.new(en: r[3])  # MultilingualString

                  @action.entries << e
                end
              end
            else
              # Fallback to the original implementation if we couldn't find the row with telegraph offices and office codes
              entry_rows.each do |r|
                e = F32TDIEntry.new

                e.country_or_area = country_or_area # MultilingualString
                e.network_roa = @network_roa  # :string
                e.network_code = @network_code  # :string
                e.office_code = r[4]  # :string
                e.subarea = MultilingualString.new(en: r[3])  # MultilingualString

                @action.entries << e
              end
            end
          else
            raise "Unexpected non-string/array elem in c[0]" unless c[0].nil?
          end
        end
        amendment
      end

    end
  end
end
