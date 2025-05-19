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

        # We need to group the tables under each paragraph
        # If we have 2 consecutive tables, we need to put them under the same paragraph

        paragraph_carry = nil
        table_carry = []
        para_to_tables = {}

        # Process document content to build paragraph to tables mapping
        doc.content.each do |item|
          case item
          when Prosereflect::Paragraph
            text_content = Ituob::Helpers.replace_legacy_space(item.text_content).strip

            # Skip empty paragraphs
            next if text_content.empty?

            # Skip paragraphs that match the pattern "(Annex to ITU Operational Bulletin No. XXXX – DD.MM.YYYY) (Amendment No.XX)"
            next if text_content =~ /\(Annex to ITU Operational Bulletin No\.\s*\d+\s*[-–]\s*[\d\.A-Z]+\)\s*\(Amendment No\.\d+\)/

            # This is a valid non-empty paragraph that doesn't match the pattern to skip
            paragraph_carry = item
            para_to_tables[paragraph_carry] = []

            # Add any carried tables to this paragraph
            unless table_carry.empty?
              para_to_tables[paragraph_carry].concat(table_carry)
              table_carry = []
            end
          when Prosereflect::HardBreak
            # Ignore hard breaks
          when Prosereflect::Table
            if paragraph_carry
              # Add table to current paragraph's tables
              para_to_tables[paragraph_carry] << item
            else
              # No current paragraph, add to table_carry for the next paragraph
              table_carry << item
            end
          end
        end

        # Process each paragraph and its associated tables
        para_to_tables.each do |para, tables|
          # Parse actions metadata from paragraph
          action = parse_action_from_paragraph(para)

          # Process each table associated with this paragraph
          tables.each do |table|
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
        end

        amendment
      end

      private

      def self.parse_action_from_paragraph(paragraph)
        # Extract metadata from paragraph text
        text = paragraph.text_content
        text = Ituob::Helpers.replace_legacy_space(text).strip

        # puts "Parsing paragraph: #{paragraph.inspect}"
        # puts "Parsing paragraph: #{text.inspect}"

        # A paragraph looks like this, and may contain one or more actions:
        # "P 42 ADD"
        # "P  16 and 17   Denmark   SUP (delete)"

        # If there are 2 positions, they are separated by "and" and represents
        # multiple actions

        # Extract position (P xx)

        # Pattern: {P} {positions} {country} {action_type}
        # Example: "P 42 ADD" or "P 16 and 17 Denmark SUP (delete)" or "P  8  Bermuda   ADD"
        pattern_1 = /\AP?[[:space:]]*(?<positions>\d+[\sand]*\d+)?[[:space:]]+(?<country>[\w\s-]+)[[:space:]]+\b(?<action>(ADD|SUP|LIR|REP))\b/
        # Pattern: {action_type} {P} {positions} {country}
        # Example: "ADD  P  39   Mongolia"
        pattern_2 = /\A(?<action>(ADD|SUP|LIR|REP))\bP?[[:space:]]*(?<positions>\d+[\sand]*\d+)?[[:space:]]+(?<country>[\w\s-]+)\b/

        # Pattern (missing position)
        # Example: "Japan     ADD"
        pattern_3 = /\A(?<country>[\w\s-]+)[[:space:]]+(?<action>(ADD|SUP|LIR|REP))\b/

        # Pattern (missing action, with ellipsis)
        # Example: "Kenya…..SUP"
        pattern_4 = /\A(?<country>[\w\s-]+)…+\.*\b(?<action>(ADD|SUP|LIR|REP))\b/

        # Match the text against the patterns using rescue and loop
        match = text.match(pattern_1) || text.match(pattern_2) || text.match(pattern_3) || text.match(pattern_4)
        # puts "Match: #{match.inspect}"

        raise "Invalid paragraph format: #{text}" unless match

        # Extract the named captures
        # In pattern 3 there are no positions, so we skip
        positions = match.named_captures["positions"] if match.named_captures["positions"]

        country = match.named_captures["country"]

        if match.named_captures["action"]
          action_type = case match.named_captures["action"]
          when 'ADD'
            'ADD'
          when 'SUP'
            'SUP'
          when 'LIR', 'REP'
            'LIR'
          # when 'DEL'
          else
            raise "Unknown action type: #{match.named_captures['action']}"
          end
        end

        if positions =~ /and/
          positions = positions.split('and').map(&:strip).join(',')
        end

        E118Action.new(
          position: positions || nil,
          country: country,
          action_type: action_type
        )
      end


    end
  end
end
