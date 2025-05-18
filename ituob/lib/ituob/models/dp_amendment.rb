# frozen_string_literal: true

require_relative 'amendment'
require_relative 'dp_entry'
require_relative 'dp_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class DPAmendment < Amendment
      attribute :actions, DPAction, collection: true
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

        amendment.actions = []

        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)
          next if c.flatten[0] && c.flatten[0].match(/^Country/)

          first_elem = c[0] 
          if first_elem.is_a?(String)
            next if first_elem.length < 3 
            next unless first_elem.match(/^P/)
            basestr = c.join('')
            segs = Ituob::Helpers.split_str(basestr)

            @action = DPAction.new 
            @action.entries = []
            @action.position = segs[0..1].join(" ")
            if basestr.include?('LIR*')
              @action.action_type = 'LIR'
            elsif basestr.match(/LIR$/)
              @action.action_type = 'LIR'
            elsif segs[-1].length == 3
              @action.action_type = segs[-1]
            else
              @action.action_type = basestr[-3..-1]
            end
            amendment.actions << @action 

          elsif first_elem.is_a?(Array) # table

            # they're all one row
            @entry = DPEntry.new 
            segs = c.flatten
            @entry.country_or_area = MultilingualString.new(en: segs[0])
            @entry.country_code = segs[1]
            @entry.international_prefix = segs[2]
            @entry.national_prefix = segs[3] 
            @entry.national_sig_number = segs[4] 
            @entry.utc_dst = segs[5]
            @entry.note = segs[6]
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
