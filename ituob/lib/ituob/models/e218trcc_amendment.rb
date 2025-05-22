# frozen_string_literal: true

require_relative 'amendment'
require_relative 'e218trcc_entry'
require_relative 'e218trcc_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class E218TRCCAmendment < Amendment
      attribute :actions, E218TRCCAction, collection: true
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


        simplified_doc = Ituob::Helpers.dump_doc(doc)

        @action = E218TRCCAction.new 
        @action.entries = []
        amendment.actions << @action 

        # These should probably just be written manually instead of through this parser...there's only 2 of these messages and the format is a mess
        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)
          next if c.inspect.include?("Country or Geographical Area")
          next if c.flatten[0] && c.flatten[0].match(/^Code/)


          first_elem = c[0] 
          if first_elem.is_a?(String)
            next if first_elem.length < 3 
            next unless first_elem.match(/.*Order.*ADD/)
            basestr = c.join('')
            segs = Ituob::Helpers.split_str(basestr)

            @action = E218TRCCAction.new 
            @action.entries = []
            @action.position = segs[0..-2].join(" ")
            @action.action_type = segs[-1]
            amendment.actions << @action 

          elsif first_elem.is_a?(Array) # table

            # they're all one row
            @entry = E218TRCCEntry.new 
            segs = c.flatten
            @entry.tmcc_code = first_elem[0]
            @entry.country_or_area = MultilingualString.new(en: first_elem[1])
            # @entry.reserved = 
            @entry.note = MultilingualString.new(en: first_elem[2])

            @action.entries << @entry
          else
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end
        amendment
      end

    end
  end
end
