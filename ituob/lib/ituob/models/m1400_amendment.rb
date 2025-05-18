# frozen_string_literal: true

require_relative 'amendment'
require_relative 'm1400_entry'
require_relative 'm1400_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class M1400Amendment < Amendment
      attribute :actions, M1400Action, collection: true
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

        @action = M1400Action.new 
        @action.entries = []
        amendment.actions << @action 

        @country = nil
        @country_code = nil

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each_with_index do |c, ci|
          next if c.nil?
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0] 
          if first_elem.is_a?(String)
            fixed_str = Ituob::Helpers.replace_legacy_space(c.join(' '))

            if first_elem.length < 3 
              next
            else
              next unless fixed_str.match(/^.*\/.*[A-Z]{3}$/)
              segs = Ituob::Helpers.split_str(fixed_str)

              @action.note = segs[1]
              @action.position = segs[0..1].join(" ")
              if m = fixed_str.match(/[A-Z]{3}\*$/)
                @action.action_type = m[0].to_s
              elsif m = fixed_str.match(/[A-Z]{3}$/)
                @action.action_type = m[0].to_s
              end
              if fixed_str.match(/^P /)
                @country, @country_code = segs[2].split(' / ')
              else
                @country, @country_code = segs[0].split(' / ')
              end
            end

          elsif first_elem.is_a?(Array) # table
            flattened = c.flatten

            # assumes 3 row tables, seems to be the most common one
            c[1..].each do |row|
              rf = Ituob::Helpers.replace_legacy_space(row.flatten.join('')).strip
              next if rf.match(/^Country/) 
              next if rf.match(/Company.Name/) 
              if rf.match(/.* \/ ([A-Z]{3})$/)
                @country, @country_code = rf.split(' / ')
                next
              end
              m = rf.match(/(.*) \/ ([A-Z]{3}).+([A-Z]{3})$/)
              if m 
                # This seems to actually trigger a new action 
                @action = M1400Action.new 
                @action.entries = []
                @action.action_type == m[3]
                @country = m[1]
                @country_code = m[2]
                amendment.actions << @action 
                next
              end
              next if rf.nil? or rf.length == 0
              segs = row.flatten
              @entry = M1400Entry.new 

              @entry.iso_code = @country_code
              @entry.country_or_area = MultilingualString.new(en: @country)
              @entry.company_name = Ituob::Helpers.strip_legacy(row[0][0]) rescue nil
              @entry.address_line_1 = Ituob::Helpers.strip_legacy([0][1]) rescue nil
              @entry.address_line_2 = Ituob::Helpers.strip_legacy([0][2]) rescue nil
              @entry.address_line_3 = Ituob::Helpers.strip_legacy([0][3]) rescue nil
              @entry.carrier_code = Ituob::Helpers.strip_legacy([1][0]) rescue nil
              @entry.contact = Ituob::Helpers.strip_legacy([2][0]) rescue nil
              @entry.fax = Ituob::Helpers.isolate_key(row[2], 'Fax')
              @entry.tel = Ituob::Helpers.isolate_key(row[2], 'Tel.')
              @entry.email = Ituob::Helpers.isolate_key(row[2], 'Email')

              @action.entries << @entry
            end
            @action = M1400Action.new 
            @action.entries = []
            amendment.actions << @action 
          else
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end

        amendment.actions = amendment.actions.filter{|x| x.entries.length > 0}
      end

    end
  end
end
