# frozen_string_literal: true

require_relative 'amendment'
require_relative 'rr251_entry'
require_relative 'rr251_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class RR251Amendment < Amendment
      attribute :actions, RR251Action, collection: true
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

        @action = RR251Action.new 
        @action.entries = []

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0] 
          if first_elem.is_a?(String)
            str = Ituob::Helpers.replace_legacy_space(first_elem)

            if parse_state[:elem] == 'table'
              # reinitialize action
              if @action
                amendment.actions << @action
                @action = RR251Action.new 
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
                @network_roa = tc[1][0].strip
                @network_code = tc[2][0].strip
              elsif tc.count == 5
                entry_rows << tc.map{|x| Ituob::Helpers.replace_legacy_space(x[0]).strip }
              end
            end

            countries = c.map{|x| x[0]}.flatten.select{|x|x.length > 1 && x != "1" && !x.match(/^Country/)}
            country_or_area = MultilingualString.new( fr: countries[0], en: countries[1], es: countries[2] )

            network = entry_rows.map{|x|x[1]}.flatten.select{|x|x.length > 0}.join(" ")
        
            entry_rows.each do |r|
              e = RR251Entry.new

              e.country_or_area = country_or_area # MultilingualString
              # e.country_or_area_note =   # MultilingualString
              # e.notes =   # MultilingualString
              e.network_roa = @network_roa  # :string
              #e.network_roa_note =   # :string
              e.network_code = @network_code  # :string
              #e.network_code_note =   # MultilingualString
              #e.telegraph_office_name =   # MultilingualString
              e.office_code = r[4]  # :string
              #e.office_code_note =   # MultilingualString
              e.subarea = r[3]  # MultilingualString

              @action.entries << e 
            end
          else
            raise "Unexpected non-string/array elem in c[0]"
          end
        end
        amendment
      end

    end
  end
end
