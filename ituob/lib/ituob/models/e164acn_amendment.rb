# frozen_string_literal: true

require_relative 'amendment'
require_relative 'e164acn_entry'
require_relative 'e164acn_action'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class E164ACNAmendment < Amendment
      attribute :actions, E164ACNAction, collection: true
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

      def self.extract_text_from_cell(cell)
        return nil unless cell

        # Try to extract text from the cell's content
        if cell["content"] && cell["content"].first && cell["content"].first["content"]
          paragraph = cell["content"].first
          if paragraph["content"] && paragraph["content"].first && paragraph["content"].first["text"]
            return paragraph["content"].first["text"]
          end
        end

        # If we couldn't extract text using the above method, try a different approach
        if cell["content"] && cell["content"].first
          if cell["content"].first["text"]
            return cell["content"].first["text"]
          elsif cell["content"].first["content"] && cell["content"].first["content"].first
            if cell["content"].first["content"].first["text"]
              return cell["content"].first["content"].first["text"]
            end
          end
        end

        # Return nil if we couldn't extract any text
        nil
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new

        # Set the position_on if it exists
        amendment.position_on = position_on if position_on

        doc = Prosereflect::Parser.parse_document(hash)

        # Process document content to build paragraph to tables mapping
        paragraph_carry = nil
        table_carry = []
        para_to_tables = {}

        # Process document content to build paragraph to tables mapping
        doc.content.each do |item|
          case item
          when Prosereflect::Paragraph
            text_content = Ituob::Helpers.strip_legacy(item.text_content)

            # Skip empty paragraphs
            next if text_content.empty?

            # This is a valid non-empty paragraph
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
          # Parse action from paragraph
          text = Ituob::Helpers.strip_legacy(para.text_content)
          puts "DEBUG: Processing paragraph: '#{text}'"

          # Skip header rows or empty paragraphs
          if text.match(/^Country/) || text.empty?
            puts "DEBUG: Skipping header or empty paragraph"
            next
          end
          if text.match(/^Notes common to Numerical and Alphabetical/)
            puts "DEBUG: Skipping notes paragraph"
            next
          end

          # Extract position and action type
          position_match = text.match(/^P?[[:space:]]*(?<position>\d+)/)
          position = position_match ? position_match[:position] : text.split.first
          puts "DEBUG: Position: #{position}"

          action_type = nil
          if text.include?('LIR*') || text.match(/LIR$/)
            action_type = 'LIR'
          elsif text.match(/(ADD|SUP|REP)$/)
            action_type = $1
          else
            # Try to extract the last 3 characters as action type
            last_word = text.split.last
            action_type = last_word.length == 3 ? last_word : text[-3..-1]
          end
          puts "DEBUG: Action type: #{action_type}"

          # Create a new action
          action = E164ACNAction.new(
            action_type: action_type,
            position: position,
            entries: []
          )

          # Process tables associated with this paragraph
          puts "DEBUG: Tables count: #{tables.size}"

          # Let's try a different approach - process the raw document directly
          if hash["content"]
            puts "DEBUG: Processing raw document content"

            # Find tables in the raw document
            hash["content"].each_with_index do |item, item_index|
              next unless item["type"] == "table"

              puts "DEBUG: Found table in raw document at index #{item_index}"

              # Skip the header table (first table)
              if item_index == 0
                puts "DEBUG: Skipping header table"
                next
              end

              # Process rows in the table
              if item["content"] && item["content"].is_a?(Array)
                puts "DEBUG: Table has #{item["content"].size} rows"

                item["content"].each_with_index do |row, row_index|
                  puts "DEBUG: Processing row #{row_index}"

                  # Skip if not a table row
                  next unless row["type"] == "table_row"

                  # Get cells from the row
                  cells = row["content"]
                  if cells && cells.is_a?(Array)
                    puts "DEBUG: Row has #{cells.size} cells"

                    # Skip header rows
                    first_cell_text = extract_text_from_cell(cells[0])
                    if first_cell_text && first_cell_text.match(/Country/)
                      puts "DEBUG: Skipping header row with text: #{first_cell_text}"
                      next
                    end

                    # Create a new entry
                    entry = E164ACNEntry.new

                    # Extract data from cells
                    if cells.size >= 3
                      # Extract text from each cell
                      country = extract_text_from_cell(cells[0])
                      code = extract_text_from_cell(cells[1])
                      mobile = extract_text_from_cell(cells[2])

                      puts "DEBUG: Extracted values - country: #{country}, code: #{code}, mobile: #{mobile}"

                      if country && code && mobile
                        entry.country_or_area = MultilingualString.new(
                          en: Ituob::Helpers.strip_legacy(country)
                        )
                        entry.country_code = Ituob::Helpers.strip_legacy(code)
                        entry.mobile_telephone_numbers = MultilingualString.new(
                          en: Ituob::Helpers.strip_legacy(mobile)
                        )
                        puts "DEBUG: Created entry: #{entry.country_or_area.en}, #{entry.country_code}, #{entry.mobile_telephone_numbers.en}"

                        # Add entry to action
                        action.entries << entry
                        puts "DEBUG: Added entry to action, entries count: #{action.entries.size}"
                      else
                        puts "DEBUG: Could not extract all cell values"
                      end
                    else
                      puts "DEBUG: Not enough cells in row"
                    end
                  else
                    puts "DEBUG: No cells in row or not an array"
                  end
                end
              else
                puts "DEBUG: Table has no content or content is not an array"
              end
            end
          else
            puts "DEBUG: No content in raw document"
          end

          # Add action to amendment if it has entries
          if action.entries.any?
            amendment.actions << action
            puts "DEBUG: Added action to amendment, actions count: #{amendment.actions.size}"
          else
            puts "DEBUG: No entries in action, skipping"
          end
        end

        amendment
      end
    end
  end
end
