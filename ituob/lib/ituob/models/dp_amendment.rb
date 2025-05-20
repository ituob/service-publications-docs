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
        @actions = []
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new

        # Set the position_on if it exists
        amendment.position_on = position_on if position_on

        doc = Prosereflect::Parser.parse_document(hash)

        # Debug logging
        puts "Document has #{doc.content.size} top-level elements" if ENV['DEBUG']

        # Gather action paragraphs and data tables
        action_paragraphs = []
        data_tables = []
        header_table = nil

        # First pass: identify action paragraphs and tables
        doc.content.each_with_index do |item, index|
          if item.is_a?(Prosereflect::Paragraph)
            text = Ituob::Helpers.strip_legacy(item.text_content)
            # Skip empty paragraphs
            next if text.empty?

            # Skip header paragraphs
            next if text =~ /^Country\s*\/\s*geographical area/i
            next if text =~ /\(Annex to ITU Operational Bulletin No\.\s*\d+\s*[-–]\s*[\d\.A-Z]+\)\s*\(Amendment No\.\d+\)/

            # Check if this is an action paragraph (contains P digit and/or action type)
            if text =~ /\AP\s*\d+/ || text =~ /\bLIR\b|\bADD\b|\bSUP\b/i
              action_paragraphs << { index: index, paragraph: item, text: text }
            end
          elsif item.is_a?(Prosereflect::Table)
            # First table is usually the header table
            if header_table.nil? && item.data_rows.any? &&
               item.data_rows[0].text_content.strip =~ /^Country\s*\/\s*geographical area/i
              header_table = item
            else
              # This is a data table
              data_tables << { index: index, table: item }
            end
          end
        end

        puts "Found #{action_paragraphs.size} action paragraphs and #{data_tables.size} data tables" if ENV['DEBUG']

        # Second pass: match action paragraphs with their data tables
        action_paragraphs.each_with_index do |action_data, i|
          # Parse the action from the paragraph
          action = parse_action_from_paragraph(action_data[:paragraph])

          puts "Processing action paragraph: '#{action_data[:text]}'" if ENV['DEBUG']
          puts "  - Action type: #{action.action_type}, position: #{action.position}" if ENV['DEBUG']

          # Find the closest data table after this paragraph
          next_table = nil
          next_table_index = nil

          # Find a table that appears right after this paragraph
          data_tables.each_with_index do |table_data, idx|
            # We want the first table that appears after this paragraph
            if table_data[:index] > action_data[:index]
              next_table = table_data[:table]
              next_table_index = idx
              puts "  - Found corresponding table at index #{table_data[:index]}" if ENV['DEBUG']
              break
            end
          end

          # If we found a table
          if next_table
            # Skip if it's a header table
            if next_table.data_rows.size == 1 &&
               Ituob::Helpers.strip_legacy(next_table.data_rows[0].text_content) =~ /^Country\s*\/\s*geographical area/i
              puts "  - Skipping header table" if ENV['DEBUG']
              next
            end

            # Handle rowspans if present
            handle_rowspans(next_table)

            # For direct access to table data when using Prosereflect
            if next_table.respond_to?(:content) && next_table.content.is_a?(Array)
              puts "  - Using direct table.content access with #{next_table.content.size} rows" if ENV['DEBUG']

              # Skip the first row if it's a header
              first_row = next_table.content[0]
              start_idx = 0

              if first_row && first_row.respond_to?(:content) &&
                 first_row.content[0] &&
                 first_row.content[0].text_content.to_s =~ /^Country\s*\/\s*geographical area/i
                puts "  - Skipping header row" if ENV['DEBUG']
                start_idx = 1
              end

              # Process each row directly from content
              (start_idx...next_table.content.size).each do |i|
                row = next_table.content[i]

                # Skip empty rows
                next unless row.respond_to?(:content) && row.content.is_a?(Array) && row.content.any?

                cells = row.content

                # Create DP entry
                entry = DPEntry.new

                # Process cells directly
                begin
                  # Country/geographical area
                  if cells[0] && cells[0].respond_to?(:content) && cells[0].content.any?
                    country_text = Ituob::Helpers.strip_legacy(cells[0].text_content)
                    if !country_text.empty?
                      puts "  - Found country: '#{country_text}'" if ENV['DEBUG']
                      entry.country_or_area = Ituob::Models::MultilingualString.new(en: country_text)
                    end
                  end

                  # Country Code
                  if cells[1] && cells[1].respond_to?(:content)
                    code = Ituob::Helpers.strip_legacy(cells[1].text_content)
                    if !code.empty?
                      entry.country_code = code
                      puts "  - Found country code: '#{code}'" if ENV['DEBUG']
                    end
                  end

                  # International prefix
                  if cells[2] && cells[2].respond_to?(:content)
                    prefix = Ituob::Helpers.strip_legacy(cells[2].text_content)
                    if !prefix.empty?
                      entry.international_prefix = prefix
                      puts "  - Found int prefix: '#{prefix}'" if ENV['DEBUG']
                    end
                  end

                  # National prefix
                  if cells[3] && cells[3].respond_to?(:content)
                    nat_prefix = Ituob::Helpers.strip_legacy(cells[3].text_content)
                    if !nat_prefix.empty?
                      entry.national_prefix = nat_prefix
                      puts "  - Found nat prefix: '#{nat_prefix}'" if ENV['DEBUG']
                    end
                  end

                  # National (Significant) Number
                  if cells[4] && cells[4].respond_to?(:content)
                    sig_num = Ituob::Helpers.strip_legacy(cells[4].text_content)
                    if !sig_num.empty?
                      entry.national_sig_number = sig_num
                      puts "  - Found nat sig num: '#{sig_num}'" if ENV['DEBUG']
                    end
                  end

                  # UTC/DST
                  if cells[5] && cells[5].respond_to?(:content)
                    utc = Ituob::Helpers.strip_legacy(cells[5].text_content)
                    if !utc.empty?
                      entry.utc_dst = utc
                      puts "  - Found UTC/DST: '#{utc}'" if ENV['DEBUG']
                    end
                  end

                  # Note
                  if cells[6] && cells[6].respond_to?(:content)
                    note = Ituob::Helpers.strip_legacy(cells[6].text_content)
                    if !note.empty?
                      entry.note = Ituob::Models::MultilingualString.new(en: note)
                      puts "  - Found note: '#{note}'" if ENV['DEBUG']
                    end
                  end

                  # Only process if we have country info
                  if entry.respond_to?(:country_or_area) && entry.country_or_area
                    # Create a new action with this entry
                    begin
                      new_action = DPAction.new(
                        action_type: action.action_type,
                        position: action.position
                      )
                      # Make sure entries is initialized
                      if new_action.entries.nil?
                        puts "  - entries is nil, initializing..." if ENV['DEBUG']
                        new_action.instance_variable_set(:@entries, [])
                      end

                      # Now add the entry
                      new_action.entries << entry
                      puts "  - Entry added to action's entries list" if ENV['DEBUG']

                      # Make sure amendment.actions is initialized
                      if amendment.actions.nil?
                        puts "  - amendment.actions is nil, initializing..." if ENV['DEBUG']
                        amendment.instance_variable_set(:@actions, [])
                      end

                      # Now add the action
                      amendment.actions << new_action
                      puts "  - Action added to amendment's actions list" if ENV['DEBUG']
                    rescue => e
                      puts "  - Error adding entry to action: #{e.message}" if ENV['DEBUG']
                      puts e.backtrace.join("\n") if ENV['DEBUG']
                    end

                    puts "  - Added action with position #{action.position}, type #{action.action_type}, country #{entry.country_or_area.en}" if ENV['DEBUG']
                  else
                    puts "  - Skipping row without country" if ENV['DEBUG']
                  end
                rescue => e
                  puts "  - Error processing row: #{e.message}" if ENV['DEBUG']
                  puts e.backtrace.join("\n") if ENV['DEBUG']
                end
              end
            else
              # Fallback to using data_rows if content isn't accessible
              puts "  - Using data_rows access" if ENV['DEBUG']

              # Process each row in the table
              next_table.data_rows.each do |row|
                # Skip empty or header rows
                if row.cells.empty? ||
                   (row.cells[0] && row.cells[0].text_content.strip =~ /^Country\s*\/\s*geographical area/i)
                  puts "  - Skipping empty or header row" if ENV['DEBUG']
                  next
                end

                # Parse the entry from this row
                entry = parse_entry_from_row(row)

                # Skip if entry couldn't be parsed
                unless entry
                  puts "  - Could not parse entry from row" if ENV['DEBUG']
                  next
                end

                # Create a new action with this entry
                begin
                  new_action = DPAction.new(
                    action_type: action.action_type,
                    position: action.position
                  )
                  # Make sure entries is initialized
                  if new_action.entries.nil?
                    puts "  - entries is nil, initializing..." if ENV['DEBUG']
                    new_action.instance_variable_set(:@entries, [])
                  end

                  # Now add the entry
                  new_action.entries << entry
                  puts "  - Entry added to action's entries list" if ENV['DEBUG']

                  # Make sure amendment.actions is initialized
                  if amendment.actions.nil?
                    puts "  - amendment.actions is nil, initializing..." if ENV['DEBUG']
                    amendment.instance_variable_set(:@actions, [])
                  end

                  # Now add the action
                  amendment.actions << new_action
                  puts "  - Action added to amendment's actions list" if ENV['DEBUG']
                rescue => e
                  puts "  - Error adding entry to action: #{e.message}" if ENV['DEBUG']
                  puts e.backtrace.join("\n") if ENV['DEBUG']
                end

                puts "  - Added action with position #{action.position}, type #{action.action_type}, country #{entry.country_or_area&.en}" if ENV['DEBUG']
              end
            end

            # Remove this table so it isn't processed again
            data_tables.delete_at(next_table_index) if next_table_index
          else
            puts "  - No corresponding table found!" if ENV['DEBUG']
          end
        end

        amendment
      end

      private

      def self.handle_rowspans(table)
        return unless table.data_rows.any?

        # Check if the first cell has rowspan
        first_row = table.data_rows[0]
        return unless first_row && first_row.cells.any?

        country_cell = first_row.cells[0]
        return unless country_cell.attrs

        rowspan = country_cell.attrs['rowspan'].to_i

        if rowspan > 1
          (1...rowspan).each do |i|
            if i < table.data_rows.length && table.data_rows[i]
              # Clone the country cell and add it to subsequent rows
              table.data_rows[i].content.prepend(country_cell.clone)
            end
          end
        end
      end

      def self.parse_entry_from_row(row)
        return nil unless row && row.respond_to?(:cells) && row.cells

        cells = row.cells
        return nil if cells.empty?

        puts "Processing row with #{cells.length} cells" if ENV['DEBUG']
        cells.each_with_index do |cell, i|
          puts "  - Cell #{i}: '#{cell.text_content.strip}'" if ENV['DEBUG']
        end

        entry = DPEntry.new

        # Map cells to entry fields
        begin
          # Make sure we have access to MultilingualString class
          unless defined?(Ituob::Models::MultilingualString)
            puts "MultilingualString not defined, ensuring it's available..." if ENV['DEBUG']
            # No need to require as it should be already loaded
          end

          # Country/geographical area
          if cells[0]
            country_text = cells[0].text_content.strip
            country_text = country_text.gsub(/\s+/, ' ').strip
            if !country_text.empty?
              puts "  - Found country: '#{country_text}'" if ENV['DEBUG']
              # Create MultilingualString manually to ensure it's working
              begin
                multi_string = Ituob::Models::MultilingualString.new(en: country_text)
                entry.country_or_area = multi_string
                puts "  - Successfully set country_or_area" if ENV['DEBUG']
              rescue => e
                puts "  - Error creating MultilingualString: #{e.message}" if ENV['DEBUG']
                # Fallback: try direct assignment if available
                entry.country_or_area = Ituob::Models::MultilingualString.new
                entry.country_or_area.en = country_text
                puts "  - Used fallback direct assignment" if ENV['DEBUG']
              end
            end
          end

          # Country Code
          if cells[1] && !cells[1].text_content.strip.empty?
            entry.country_code = cells[1].text_content.strip
            puts "  - Found country code: '#{entry.country_code}'" if ENV['DEBUG']
          end

          # International prefix
          if cells[2] && !cells[2].text_content.strip.empty?
            entry.international_prefix = cells[2].text_content.strip
            puts "  - Found int prefix: '#{entry.international_prefix}'" if ENV['DEBUG']
          end

          # National prefix
          if cells[3] && !cells[3].text_content.strip.empty?
            entry.national_prefix = cells[3].text_content.strip
            puts "  - Found nat prefix: '#{entry.national_prefix}'" if ENV['DEBUG']
          end

          # National (Significant) Number
          if cells[4] && !cells[4].text_content.strip.empty?
            entry.national_sig_number = cells[4].text_content.strip
            puts "  - Found nat sig num: '#{entry.national_sig_number}'" if ENV['DEBUG']
          end

          # UTC/DST
          if cells[5] && !cells[5].text_content.strip.empty?
            entry.utc_dst = cells[5].text_content.strip
            puts "  - Found UTC/DST: '#{entry.utc_dst}'" if ENV['DEBUG']
          end

          # Note
          if cells[6] && !cells[6].text_content.strip.empty?
            note_text = cells[6].text_content.strip
            begin
              entry.note = Ituob::Models::MultilingualString.new(en: note_text)
              puts "  - Successfully set note" if ENV['DEBUG']
            rescue => e
              puts "  - Error creating MultilingualString for note: #{e.message}" if ENV['DEBUG']
              # Fallback
              entry.note = Ituob::Models::MultilingualString.new
              entry.note.en = note_text
              puts "  - Used fallback direct assignment for note" if ENV['DEBUG']
            end
          end
        rescue => e
          puts "Error parsing row: #{e.message}" if ENV['DEBUG']
          puts e.backtrace.join("\n") if ENV['DEBUG']
          return nil
        end

        # Only return entry if at least country_or_area is present
        if entry.respond_to?(:country_or_area) && entry.country_or_area
          puts "  - Successfully created entry for #{entry.country_or_area.is_a?(Hash) ? entry.country_or_area['en'] : entry.country_or_area.en}" if ENV['DEBUG']
          return entry
        else
          puts "  - Failed to create entry (no country/area)" if ENV['DEBUG']
          return nil
        end
      end

      def self.parse_action_from_paragraph(paragraph)
        # Extract metadata from paragraph text
        text = paragraph.text_content
        text = Ituob::Helpers.strip_legacy(text)

        # Various patterns to match different formats:

        # Pattern: "P xx Country LIR"
        pattern_1 = /\AP\s*(?<positions>\d+)\s+(?<country>[\w\s,ç\.\(\)-]+)?\s+(?<action>(ADD|SUP|LIR))/i

        # Pattern: "P XX LIR"
        pattern_2 = /\AP\s*(?<positions>\d+)\s+(?<action>(ADD|SUP|LIR))/i

        # Pattern: "P XX" followed by emphasized country name and action type
        pattern_3 = /\AP\s*(?<positions>\d+)(\s+|\s*$)/i

        # Match the text against the patterns
        match = text.match(pattern_1) || text.match(pattern_2) || text.match(pattern_3)

        # Default action if no match
        if !match
          return DPAction.new(position: nil, action_type: 'ADD')
        end

        position = match.named_captures["positions"]
        position = Ituob::Helpers.strip_legacy(position) if position

        # Determine action type
        action_type = if match.named_captures["action"]
          case match.named_captures["action"].upcase
          when 'ADD'
            'ADD'
          when 'SUP'
            'SUP'
          when 'LIR'
            'LIR'
          else
            'ADD' # Default to ADD if action is unknown
          end
        else
          # If pattern doesn't include action, check if LIR, SUP, or ADD appears anywhere in the text
          if text.include?('LIR')
            'LIR'
          elsif text.include?('SUP')
            'SUP'
          elsif text.include?('ADD')
            'ADD'
          else
            'LIR'  # Default to LIR (most common for DP amendments)
          end
        end

        DPAction.new(
          position: position ? "P #{position}" : nil,
          action_type: action_type
        )
      end
    end
  end
end
