# frozen_string_literal: true

require_relative 'amendment'
require_relative 'q708ispc_entry'
require_relative 'q708ispc_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class Q708ISPCAmendment < Amendment
      attribute :actions, Q708ISPCAction, collection: true
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

        @country = nil 

        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0] 
          if first_elem.is_a?(String) || (first_elem.is_a?(Array) && first_elem.flatten.length == 1)
            # not sure this ever gets hit for these messages
            basestr = c.join('')
            fixed_str = Ituob::Helpers.replace_legacy_space(basestr)
            next if first_elem.length < 3 
            next unless fixed_str.match(/^P /) || fixed_str.match(/[A-Z]{3}$/)
            segs = Ituob::Helpers.split_str(basestr)

            @action = Q708ISPCAction.new 
            @action.entries = []
            @action.position = segs[0..1].join(" ")
            @country = segs[2]
            if match = basestr.match(/([A-Z]{3})\*?$/)
              @action.action_type = match[1]
            end
            amendment.actions << @action 

          elsif first_elem.is_a?(Array) # table

            c.each do |r|
              rf = r.flatten
              next if rf.count == 0
              next if rf[0] && (rf[0].match(/^Country/) || rf[0].match(/^ISPC/))
              basestr = rf.join(' ')
              fixed_str = Ituob::Helpers.replace_legacy_space(basestr)
              segs = Ituob::Helpers.split_str_normal(fixed_str)
              single_space_str = segs.join(' ')

              matched = true

              # "P 100 to P 101 Hong Kong, China ADD" 
              if match = single_space_str.match(/^(P [0-9]+ to P [0-9]+) (.+) (ADD|LIR|SUP)\*?$/)
                @action = Q708ISPCAction.new 
                @action.entries = []
                @action.position = match[1].strip
                @country = match[2].strip
                if match2 = basestr.match(/([A-Z]{3})\*?$/)
                  @action.action_type = match2[3]
                end
                amendment.actions << @action 

              # "P 100 to P 101 Belgium"
              elsif match = fixed_str.match(/^(P [0-9]+ to P [0-9]+) (.*)$/)
                @action = Q708ISPCAction.new 
                @action.entries = []
                @action.position = match[1].strip
                @country = match[2].strip
                # @action.action_type = match2[3]
                amendment.actions << @action 

              #  "P  3     Afghanistan    ADD"  
              elsif fixed_str.match(/^P /) && fixed_str.match(/(ADD|LIR|SUP)$/) 
                @action = Q708ISPCAction.new 
                @action.entries = []
                @action.position = segs[0..1].join(" ")
                if segs.length > 4
                  @country = segs[2..-2].join(' ')
                else
                  @country = segs[2]
                end
                if match = basestr.match(/([A-Z]{3})\*?$/)
                  @action.action_type = match[1]
                end
                amendment.actions << @action 

              #  "ADD  P 23 Costa Rica" 
              elsif segs[1] == 'P' && segs[0].match(/^(ADD|LIR|SUP)\*?$/)
                @action = Q708ISPCAction.new 
                @action.entries = []
                @action.position = segs[1..2].join(" ")
                @country = segs[3..-1].join(' ')
                @action.action_type = segs[0]
                amendment.actions << @action 

              # "Netherlands LIR" or "Costa Rica ADD" or "Belgium ADD"
              elsif match = fixed_str.match(/^(.+) (ADD|LIR|SUP)\*?$/)
                @action = Q708ISPCAction.new 
                @action.entries = []
                # @action.position = match[1].strip # no position supplied
                @country = segs[0..-2].join(' ')
                @action.action_type = segs[-1]
                amendment.actions << @action 

              # actual data row
              else
                matched = false

                @entry = Q708ISPCEntry.new 
                @entry.ipsc = Ituob::Helpers.strip_legacy(rf[0])
                @entry.country = MultilingualString.new(en: @country)
                @entry.dec = Ituob::Helpers.strip_legacy(rf[1])
                @entry.signal_point_name = Ituob::Helpers.strip_legacy(rf[2])
                @entry.signal_point_operator = Ituob::Helpers.strip_legacy(rf[3])
                @action.entries << @entry
              end

            end
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
