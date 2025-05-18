# frozen_string_literal: true

require_relative 'amendment'
require_relative 'entry'
require_relative 't35na_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class T35NAAmendment < Amendment
      attribute :actions, T35NAAction, collection: true
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

        @action = T35NAAction.new 
        @entry = T35NAEntry.new 
        @action.entries = [@entry] # all one entry 
        amendment.actions << @action 

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each_with_index do |c, ci|
          next if c.nil?
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0] 
          if first_elem.is_a?(String)
            next unless first_elem.match(/^P/)
            fixed_str = Ituob::Helpers.replace_legacy_space(c.join(' '))
            segs = Ituob::Helpers.split_str_normal(fixed_str)
            @action.position = segs[0..1].join(' ')
            country_and_action_type = segs[-2..-1]
            cpos, atpos = country_and_action_type[0].match(/(ADD|SUP|LIR)/) ? [1,0] : [0,1]
            @entry.country = country_and_action_type[cpos]
            @action.action_type = country_and_action_type[atpos]

          elsif first_elem.is_a?(Array) # table
            @entry.manufactures_htv = 'YES' # always true 
            @entry.administration_name = Ituob::Helpers.grabcol2(c, "Name of Administration:")
            @entry.assignment_authority = [{
               terminal_type: Ituob::Helpers.grabcol2(c, "Terminal Type:"),
               contact_name: Ituob::Helpers.grabcol2(c, "Contact name:"),
               organization: Ituob::Helpers.grabcol2(c, "Organization:"),
               department: Ituob::Helpers.grabcol2(c, "Department:"),
               address: Ituob::Helpers.grabcol2(c, "Address:"),
               telephone: Ituob::Helpers.grabcol2(c, "Telephone:"),
               fax: Ituob::Helpers.grabcol2(c, "Fax:"),
               email: Ituob::Helpers.grabcol2(c, "E-mail:"),
               related_links: [Ituob::Helpers.grabcol2(c, "Related links:")]
            }]
            @entry.last_updated = Ituob::Helpers.grabcol2(c, "Information updated:")

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
