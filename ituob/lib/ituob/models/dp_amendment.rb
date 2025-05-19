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
            segs = c.flatten.map { |x| Ituob::Helpers.strip_legacy(x) }
            @entry.country_or_area = MultilingualString.new(en: segs[0])
            @entry.country_code = segs[1] unless segs[1].nil? || segs[1].empty?
            @entry.international_prefix = segs[2] unless segs[2].nil? || segs[2].empty?
            @entry.national_prefix = segs[3] unless segs[3].nil? || segs[3].empty?
            @entry.national_sig_number = segs[4] unless segs[4].nil? || segs[4].empty?
            @entry.utc_dst = segs[5] unless segs[5].nil? || segs[5].empty?
            @entry.note = MultilingualString.new(en: segs[6]) unless segs[6].nil? || segs[6].empty?

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
