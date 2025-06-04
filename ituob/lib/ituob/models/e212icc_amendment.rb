# frozen_string_literal: true

require_relative 'amendment'
require_relative 'e212icc_entry'
require_relative 'e212icc_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class E212ICCAmendment < Amendment
      attribute :actions, E212ICCAction, collection: true
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

        @amendment_notes_only = false
        @amendment_notes = []
        @current_action = nil # sanity check to throw if it's accessed incorrectly

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each_with_index do |c, ci|
          next if c.nil?
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0] 
          if first_elem.is_a?(String)
            fixed_str = Ituob::Helpers.replace_legacy_space(c.join(' ')).strip

            if first_elem.length < 3 
              next
            elsif first_elem =~ /^____/ || first_elem =~ /^Notes common to/
              @amendment_notes_only = true
            elsif @amendment_notes_only
              @amendment_notes << fixed_str 

            elsif fixed_str.match(/ Order/) || fixed_str.match(/ order/)
              @current_action = E212ICCAction.new 
              @current_action.entries = []
              amendment.actions << @current_action 
              segs = Ituob::Helpers.split_str_normal_double(fixed_str)
              segs.each do |s|
                if s =~ /Order/
                  @current_action.order = s 
                elsif s =~ /^P/
                  @current_action.position = s 
                elsif s =~ /(LIR|ADD|SUP)/
                  @current_action.action_type = s 
                end
              end

            else
              next if !(first_elem.match(/^P/) || first_elem.match(/Note /))

              basestr = c.join('')
              segs = Ituob::Helpers.split_str(basestr)

              @current_action.note = segs[1]
              @current_action.position = segs[0..1].join(" ")
              if m = basestr.match(/[A-Z]{3}\*$/)
                @current_action.action_type = m[0].to_s
              elsif m = basestr.match(/[A-Z]{3}$/)
                @current_action.action_type = m[0].to_s
              elsif segs[-1].length == 3
                @current_action.action_type = segs[-1]
              else
                @current_action.action_type = basestr[-3..-1]
              end
            end

          elsif first_elem.is_a?(Array) # table
            next if first_elem[0][0] =~ /^Code/ # skip header standalone table 
            if @amendment_notes_only 
              @amendment_notes << c 
              next
            end

            c.each do |row|
              if row.all?{|x| Ituob::Helpers.strip_legacy(x[0]).length == 0}
                next
              end

              segs = row.flatten
              entry = E212ICCEntry.new 
              if segs[0] == 'P'
                #@current_action.position = segs[0] + ' ' + segs[1] # this is apparently not correct.  treating this as just blank "P"
                @current_action.position = segs[0]
                entry.code = segs[1]
                entry.country_or_area = MultilingualString.new(en: segs[2])
                entry.note = MultilingualString.new(en: segs[3])
              elsif segs[0] =~ /^P/
                @current_action.position = segs[0]
                entry.code = segs[1]
                entry.country_or_area = MultilingualString.new(en: segs[2])
                entry.note = MultilingualString.new(en: segs[3])
              else
                entry.code = segs[0]
                entry.country_or_area = MultilingualString.new(en: segs[1])
                entry.note = MultilingualString.new(en: segs[2])
              end
              @current_action.entries << entry
            end
          else
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end

        amendment.notes = @amendment_notes.flatten.join("\n")

        amendment
      end

    end
  end
end
