# frozen_string_literal: true

require_relative 'amendment'
require_relative 'x121dnic_entry'
require_relative 'x121dnic_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class X121DNICAmendment < Amendment
      attribute :actions, X121DNICAction, collection: true
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

        @action = X121DNICAction.new 
        @action.entries = []
        @action.notes = ""
        amendment.actions << @action
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
            str = Ituob::Helpers.replace_legacy_space(c.join(' '))

            if parse_state[:elem] == 'table' 
              @action.notes += str + "\n"
              next
            end

            next if str.length == 1 

            if match = str.match(/(P[ 0-9]+)/)
              @action.position = match[1].strip
              remaining = str.gsub(match[1], '')
              match2 = remaining.match(/([\w ]+) ([A-Z]{3})$/)
              if match2
                @country = match2[1]
                @action.action_type = match2[2]
              else
                if remaining.length == 3
                  @action.action_type = remaining
                end
              end
              # @action.country = segs[2]
            elsif str.match(/^206/)
              segs = Ituob::Helpers.split_str(str)
              @action.position = segs[0..1].join(" ")
              @action.action_type = segs[-1]
            elsif str.match(/^\(Annex/)
              @action.notes += str
            else 
              segs = Ituob::Helpers.split_str(str)
              #@action.position = segs[0..1].join(" ")
              @action.action_type = segs[-1]
            end
            if @action.position
              @action.position = Ituob::Helpers.remove_legacy_double_spaces(@action.position)
            end
            if @country 
              @country = Ituob::Helpers.strip_legacy(@country)
            end

          elsif first_elem.is_a?(Array) # table
            parse_state[:elem] = 'table'

            entry_rows = []
            c.each_with_index do |tc, tci|
              if tc.all?{|x| x[0].strip.length == 0}
                # discard
              elsif tc[0][0].strip.match?(/^Country/) 
                # header - discard 
              elsif tc[0][0] == "1" && tc[1][0] == "2"
                # numbers header, discard
              elsif tc.count == 3
                entry_rows << tc.map{|x| Ituob::Helpers.replace_legacy_space(x[0]).strip }
              end
            end

            countries = c.map{|x| x[0]}.flatten.select{|x|x.length > 1 && x != "1" && !x.match(/^Country/)}
            country_or_area = MultilingualString.new( fr: countries[0], en: (countries[1] || @country), es: countries[2] )

            network = entry_rows.map{|x|x[1]}.flatten.select{|x|x.length > 0}.join(" ")
        
            entry_rows.each do |r|
              next unless r[1].length > 1 && r[2].length > 1
              e = X121DNICEntry.new
              e.country_or_area = country_or_area # MultilingualString
              e.dnic_number = r[1]
              e.network_name = r[2]

              @action.entries << e 
            end
          else
            raise "Unexpected non-string/array elem in c[0]" unless c[0].nil?
          end
        end
        @action.notes = @action.notes.strip
        amendment
      end

    end
  end
end
