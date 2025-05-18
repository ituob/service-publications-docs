# frozen_string_literal: true

require_relative 'amendment'
require_relative 'entry'
require_relative 'f400_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class F400Amendment < Amendment
      attribute :actions, F400Action, collection: true
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
        amendment.actions = []

        doc = Prosereflect::Parser.parse_document(hash)
        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0] 
          if first_elem.is_a?(String)
            next if first_elem.length < 2
            next unless first_elem.match(/^P/) || first_elem.match(/[A-Z]{3}$/)
            basestr = c.join('')
            segs = Ituob::Helpers.split_str(basestr)

            @action = F400Action.new 
            @action.entries = []
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

            amendment.actions << @action 

          elsif first_elem.is_a?(Array) # table
            c.each do |row|
              next if row.flatten[0] && row.flatten[0].match(/^Country/)
              next if row.all?{|x| x[0].length < 2}
              next if row.length < 4
              next if row[0][0].match(/^Country/)

              @entry = F400Entry.new 
              if row[0].length > 2
                @entry.country_or_area = MultilingualString.new(fr: row[0][0], en: row[0][1],  es: row[0][2] )
              else
                @entry.country_or_area = MultilingualString.new(en: row[0][0])
              end
              @entry.admd_name = row[1].join(' ')
              # @entry.not_operational_yet = 
              @entry.country_code = row[2].join(' ')
              # row[3] (service name) is absent in target schema...
              # @entry.for_test_purposes, :boolean
              # @entry.mt = row[]
              # @entry.ipm = row[] 
              # @entry.other = row[]
              @entry.helpdesk = {x400: row[4].join(' ')}
              @entry.autoanswer = {x400: row[5].join(' ')}
              @entry.contact_address = {address_line_1: row[6].join(' ')} # this has serious issues in source data 
              #@entry.note = row[]

              @action.entries << @entry
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
