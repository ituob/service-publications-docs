# frozen_string_literal: true

require_relative 'amendment'
require_relative 'e164cc_entry'
require_relative 'e164cc_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class E164CCAmendment < Amendment
      attribute :actions, E164CCAction, collection: true
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

        @action = E164CCAction.new 
        @action.entries = []
        amendment.actions << @action 

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each_with_index do |c, ci|
          next if c.nil?
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0] 
          if first_elem.is_a?(String)
            fixed_str = Ituob::Helpers.replace_legacy_space(c.join(' '))

            if first_elem.length < 3 
              next
            elsif fixed_str.match(/^[onpq] /)
              @action.note = (@action.note || "") + fixed_str
            else
              next if !(first_elem.match(/^P/) || first_elem.match(/Note /))

              basestr = c.join('')
              segs = Ituob::Helpers.split_str(basestr)

              @action.note = segs[1]
              @action.position = segs[0..1].join(" ")
              if m = basestr.match(/[A-Z]{3}\*$/)
                @action.action_type = m[0].to_s
              elsif m = basestr.match(/[A-Z]{3}$/)
                @action.action_type = m[0].to_s
              elsif segs[-1].length == 3
                @action.action_type = segs[-1]
              else
                @action.action_type = basestr[-3..-1]
              end
            end

          elsif first_elem.is_a?(Array) # table
            c[1..].each do |row|
              next unless row.length == 4 
              segs = row.flatten
              entry = E164CCEntry.new 
              entry.applicant = segs[0]
              entry.network = segs[1]
              entry.cc_ic = segs[2]
              entry.status = segs[3]
              if entry.applicant.match(/Formerly/)
                entry.applicant = segs[0].match(/([^(]*)/).to_s.strip
                entry.formerly = segs[0].match(/\((.*)\)/)[1].gsub('Formerly ','').strip
              end
              # @entry.formerly = segs[]
              @action.entries << entry
            end
            @action = E164CCAction.new 
            @action.entries = []
            amendment.actions << @action 
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
