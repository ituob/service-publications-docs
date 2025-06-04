# frozen_string_literal: true

require_relative 'amendment'
require_relative 'q708sanc_entry'
require_relative 'q708sanc_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class Q708SANCAmendment < Amendment
      attribute :actions, Q708SANCAction, collection: true
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

        @note = simplified_doc.select{|x| x[0].is_a?(String) && !x[0].match(/^___/) }.flatten.map{|x| Ituob::Helpers.strip_legacy(x) }.select{|x|x.length > 0}.join("\n")

        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)
          next if c.flatten[0] && c.flatten[0].match(/^Country/)

          first_elem = c[0] 
          if first_elem.is_a?(Array) # table
            fixed_space_header = Ituob::Helpers.replace_legacy_space(first_elem.flatten.join(' '))
            segs = Ituob::Helpers.split_str_normal_double(fixed_space_header)

            c.each_with_index do |r, ri|
              rsegs = r.flatten.map{|x|Ituob::Helpers.strip_legacy(x)}
              next if ri == 0

              @action = Q708SANCAction.new 
              @action.order = segs[0..-2].join(' ')
              @action.action_type = segs[-1]
              @action.position = rsegs[0]
              @action.notes = @note
              amendment.actions << @action

              @entry = Q708SANCEntry.new 
              @entry.code = rsegs[1]
              @entry.area_or_network = MultilingualString.new(en: rsegs[2])
              @entry.note = MultilingualString.new(en: @note)

              @action.entries = [@entry]
            end
          elsif !first_elem.is_a?(String)
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end
        amendment
      end

    end
  end
end
