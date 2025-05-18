# frozen_string_literal: true

require_relative 'amendment'
require_relative 'e118_action'
require_relative 'e118_entry'
require 'prosereflect'

module Ituob
  module Models
    class E118Amendment < Amendment
      attribute :actions, E118Action, collection: true
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

        # puts "Parsing document: #{doc.inspect}"
        # Process each paragraph-table pair as an action

        # We want to drop all paragraphs that are empty or contain only hard breaks
        # and only keep the ones that have text content

        paragraphs = doc.paragraphs.select do |para|
          # Check if the paragraph is empty or contains only hard breaks
          if para.is_a?(Prosereflect::Paragraph)
            # Check if the paragraph has any text content
            para.text_content.gsub(/\A[[:space:]]+\Z/, '').length > 0
          elsif para.is_a?(Prosereflect::HardBreak)
            # Ignore hard breaks
            false
          else
            # If it's not a paragraph, we don't want it
            false
          end
        end
        tables = doc.tables

        # If we have tables but they don't match paragraphs, we need to handle differently
        if tables.size != paragraphs.size
          raise "Mismatch between tables and paragraphs: #{tables.size} tables, #{paragraphs.size} paragraphs"
        end

        # We have a matching paragraph-table pair for each action
        puts "Matching tables and paragraphs: #{tables.size} tables, #{paragraphs.size} paragraphs"

        paragraphs.each_with_index do |para, index|
          # Parse actions metadata from paragraph
          action = parse_action_from_paragraph(para)

          # Get the table for these actions
          table = tables[index]
          if table && table.data_rows.any?
            # Process the table's data rows
            # - type: table_cell
            #   attrs:
            #     colspan: 1
            #     rowspan: 3
            #     colwidth: null
            #   content:
            #     - type: paragraph
            #       content:
            #         - type: text
            #           text: Denmark
            country_cell = table.data_rows[0].cells[0]
            # If the country cell has rowspan, we need to inject this same table cell to all subsequent rows for those number of rowspans.

            # puts "+"*30
            # puts "Country cell: #{country_cell.inspect}"
            # puts "Country cell text: #{country_cell.text_content.inspect}"

            rowspan = country_cell.attrs['rowspan']
            if rowspan > 1
              (1...rowspan).each do |i|
                if table.data_rows[i]
                  # puts "Adding country cell to row #{i}: #{table.data_rows[i].inspect}"
                  table.data_rows[i].content.prepend(country_cell)
                end
              end
            end

            table.data_rows.each do |row|
              entry = E118Entry.parse(row)

              # Create a new action with this entry
              new_action = E118Action.new(
                action_type: action.action_type,
                position: action.position
              )
              new_action.entries << entry
              amendment.actions << new_action
            end
          end
        end

        amendment
      end

      private

      def self.parse_action_from_paragraph(paragraph)
        # Extract metadata from paragraph text
        text = paragraph.text_content

        # puts "Parsing paragraph: #{paragraph.inspect}"
        # puts "Parsing paragraph: #{text.inspect}"

        # A paragraph looks like this, and may contain one or more actions:
        # "P 42 ADD"
        # "P  16 and 17   Denmark   SUP (delete)"

        # If there are 2 positions, they are separated by "and" and represents
        # multiple actions

        # Extract position (P xx)
        match = text.match(/\AP[[:space:]]*(?<positions>\d+[\sand]*\d+)?[[:space:]]+(?<country>[\w\s]+)[[:space:]]+\b(?<action>[ADDSUPLIR]+)\b/)
        # puts "Match: #{match.inspect}"

        raise "Invalid paragraph format: #{text}" unless match

        positions, country, action_type = [match[:positions], match[:country], match[:action]]

        if positions =~ /and/
          positions = positions.split('and').map(&:strip).join(',')
        end

        E118Action.new(
          position: positions,
          country: country,
          action_type: action_type
        )
      end


    end
  end
end
