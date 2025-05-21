require 'lutaml/model'
require_relative 'general_message'
require_relative 'helpers'
require 'prosereflect'
require 'date'

module Ituob
  module Models
    # Entry class for IPTN messages
    class IptnEntry < Lutaml::Model::Serializable
      attribute :applicant, :string
      attribute :network, :string
      attribute :cc_ic, :string
      attribute :action, :string
      attribute :action_date, :string
      attribute :formerly, :string
      attribute :notes, :string
      attribute :reclamation_date, :string
      attribute :trial, :boolean

      key_value do
        map 'applicant', to: :applicant
        map 'network', to: :network
        map 'cc_ic', to: :cc_ic
        map 'action', to: :action
        map 'action_date', to: :action_date
        map 'formerly', to: :formerly
        map 'notes', to: :notes
        map 'reclamation_date', to: :reclamation_date
        map 'trial', to: :trial
      end
    end

    class GeneralIptn < GeneralMessage
      attribute :entries, IptnEntry, collection: true
      attribute :notes, :string
      attribute :manual, :boolean

      key_value do
        map 'type', to: :type
        map 'entries', to: :entries
        map 'notes', to: :notes
        map 'manual', to: :manual
      end

      # Extract trial information from notes
      def extract_trial_info_from_notes
        return unless notes && notes.include?('991') && notes.include?('trial')

        # Extract trial information from notes - more flexible pattern
        if notes =~ /code 991 \(CC\).*?trial.*?(?:TIC|identification code).*?"(\d+)".*?(?:until|to) (\d+\s+\w+\s+\d{4}).*?to\s+([^"\.]+?)(?:\s+for|\s+to)/i ||
           notes =~ /code 991.*?trial.*?(?:TIC|identification code).*?(\d+).*?(?:until|to) (\d+\s+\w+\s+\d{4}).*?to\s+([^"\.]+?)(?:\s+for|\s+to)/i
          tic = $1
          reclamation_date = $2
          applicant = $3.strip

          # Create a new entry for the trial
          trial_entry = IptnEntry.new
          trial_entry.applicant = applicant
          trial_entry.network = 'Trial'
          trial_entry.cc_ic = "+991 #{tic}"
          trial_entry.action = 'assigned'
          trial_entry.reclamation_date = reclamation_date
          trial_entry.trial = true

          # Extract effective date if available
          if notes =~ /effective on (\d+\.\w+\.\d{4})/i
            trial_entry.action_date = $1
          elsif notes =~ /effective on (\d+ \w+ \d{4})/i
            trial_entry.action_date = $1
          end

          # Add the trial entry to the message
          self.entries ||= []
          self.entries << trial_entry

          return trial_entry
        end

        nil
      end

      def self.parse(data)
        msg = new
        msg.type = 'iptn'
        msg.entries = []

        # If data is already in the expected format with type: iptn
        if data.is_a?(Hash) && data['type'] == 'iptn'
          if data['entries'] && data['entries'].is_a?(Array)
            msg.entries = data['entries'].map do |entry_data|
              entry = IptnEntry.new
              entry.applicant = entry_data['applicant'] if entry_data['applicant']
              entry.network = entry_data['network'] if entry_data['network']
              entry.cc_ic = entry_data['cc_ic'] if entry_data['cc_ic']
              entry.action = entry_data['action'] if entry_data['action']
              entry.action_date = entry_data['action_date'] if entry_data['action_date']
              entry.formerly = entry_data['formerly'] if entry_data['formerly']
              entry.notes = entry_data['notes'] if entry_data['notes']
              entry.reclamation_date = entry_data['reclamation_date'] if entry_data['reclamation_date']
              entry.trial = entry_data['trial'] if entry_data['trial']

              # Extract reclamation date from notes if present
              if entry.notes
                if entry.notes =~ /[Rr]eclamation date:?\s*(\d+\.\w+\.\d{4})/
                  entry.reclamation_date = $1
                elsif entry.notes =~ /until\s+(\d+\.\w+\.\d{4})/i
                  entry.reclamation_date = $1
                elsif entry.notes =~ /planned withdrawal:?\s*(\d+\.\w+\.\d{4})/i
                  entry.reclamation_date = $1
                elsif entry.notes =~ /withdraw(?:n|al) (?:date|on):?\s*(\d+\.\w+\.\d{4})/i
                  entry.reclamation_date = $1
                end
              end

              # Also check for reclamation date in the entry itself
              if !entry.reclamation_date && entry.respond_to?(:reclamation_date) && entry.reclamation_date.nil?
                # Check if there's a reclamation date in the table (for entries parsed from tables)
                if doc.content.any? { |node| node.type == "table" }
                  doc.content.each do |node|
                    if node.type == "table" && node.content && node.content.size >= 2
                      # Check if the header row has a column for reclamation date
                      header_row = node.content[0]
                      reclamation_col_index = nil

                      if header_row && header_row.content
                        header_row.content.each_with_index do |cell, idx|
                          cell_text = extract_text_with_breaks(cell).downcase
                          if cell_text.include?('reclamation') || cell_text.include?('withdrawal')
                            reclamation_col_index = idx
                            break
                          end
                        end
                      end

                      # If we found a reclamation date column, extract the date
                      if reclamation_col_index && entry.cc_ic
                        # Find the row for this entry
                        node.content.each_with_index do |row, row_idx|
                          next if row_idx == 0 # Skip header row
                          next unless row.content && row.content.size > 2

                          # Check if this row matches our entry
                          row_cc_ic = extract_text_with_breaks(row.content[2])
                          if row_cc_ic == entry.cc_ic && row.content.size > reclamation_col_index
                            reclamation_date = extract_text_with_breaks(row.content[reclamation_col_index])
                            entry.reclamation_date = reclamation_date unless reclamation_date.empty?
                          end
                        end
                      end
                    end
                  end
                end
              end

              # Set trial flag based on network, notes, or explicit indication
              if entry.network && entry.network.downcase.include?('trial')
                entry.trial = true
              elsif entry.notes && entry.notes.downcase.include?('trial')
                entry.trial = true
              elsif entry.applicant && entry.applicant.downcase.include?('trial')
                entry.trial = true
              elsif entry.cc_ic && entry.cc_ic.start_with?('+991')
                # Country code 991 is specifically for trials
                entry.trial = true
              end

              entry
            end
          end
          msg.notes = data['notes'] if data['notes']
          msg.manual = data['manual'] if data['manual']
          return msg
        end

        # Otherwise, parse from ProseMirror format
        notes = []
        current_action = nil
        current_action_date = nil
        tables = []

        # Parse the ProseMirror document using Prosereflect
        doc = Prosereflect::Parser.parse_document(data)

        # First pass: Extract action types and dates from paragraphs
        action_paragraphs = []
        doc.content.each_with_index do |node, index|
          if node.type == "paragraph"
            text = node.text_content.strip

            # Skip if empty or just whitespace
            next if text.empty?

            # Check for action information for both international networks and global mobile satellite systems
            # More flexible matching for various formats
            if text =~ /associated with shared country code \d+ for (international networks|global mobile satellite system|iot\/m2m)/i ||
               text =~ /country code (882|883|881|888|991) for (international networks|global mobile satellite system|iot\/m2m)/i ||
               text =~ /identification codes for (international networks|global mobile satellite system|international mobile networks|iot\/m2m)/i ||
               text =~ /following (identification|three-digit) code has been/i ||
               text =~ /\+(88[123]) \d+/i

              action_info = {
                index: index,
                text: text,
                action: nil,
                date: nil
              }

              # Extract action type
              if text =~ /has been assigned/i || text =~ /been assigned/i || text =~ /assigned/i
                action_info[:action] = "assigned"
              elsif text =~ /has been withdrawn/i || text =~ /been withdrawn/i || text =~ /withdrawn/i
                action_info[:action] = "withdrawn"
              elsif text =~ /has been cancelled/i || text =~ /cancelled/i
                action_info[:action] = "cancelled"
              elsif text =~ /will be reclaimed/i || text =~ /reclaimed/i
                action_info[:action] = "reclaimed"
              elsif text =~ /has been transferred/i || text =~ /been transferred/i || text =~ /transferred/i
                action_info[:action] = "transferred"
              end

              # Extract date - handle various formats including Roman numeral format
              if text =~ /on\s+(\d+\s+\w+\s+\d{4})/i
                action_info[:date] = $1
              elsif text =~ /on\s+(\w+\s+\d+,?\s+\d{4})/i
                action_info[:date] = $1
              elsif text =~ /(\d+\s+\w+\s+\d{4})/i
                action_info[:date] = $1
              elsif text =~ /(\d+\.\w+\.\d{4})/i  # Matches formats like 24.III.2025
                action_info[:date] = $1
              elsif text =~ /transfer of assignment[^\d]*(\d+\.\w+\.\d{4})/i  # For transfer dates
                action_info[:date] = $1
              end

              action_paragraphs << action_info if action_info[:action]
            end
          end
        end

        # Second pass: Find tables that follow action paragraphs
        action_paragraphs.each do |action_info|
          # Search for tables after the action paragraph
          # Look within a larger range after the action paragraph to capture tables
          search_start = action_info[:index] + 1
          search_end = [action_info[:index] + 15, doc.content.size - 1].min

          # Find the next table after this action paragraph
          table_index = nil
          (search_start..search_end).each do |i|
            if doc.content[i].type == "table"
              table_index = i
              break
            end
          end

          # Skip if no table found
          next unless table_index

          table = doc.content[table_index]

          # Skip if table doesn't have at least 2 rows (header + data)
          next if !table.content || table.content.size < 2

          # Process each data row in the table
          table.content.each_with_index do |row, row_index|
            # Skip header row
            next if row_index == 0

            # Skip if row doesn't have at least 3 cells
            next if !row.content || row.content.size < 3

            entry = IptnEntry.new

            # Extract data from cells and handle hard breaks
            entry.applicant = extract_text_with_breaks(row.content[0])
            entry.network = extract_text_with_breaks(row.content[1])
            entry.cc_ic = extract_text_with_breaks(row.content[2])
            entry.action = action_info[:action]

            # Check if date is in the table (4th column) or in the paragraph
            if row.content.size >= 4 && row.content[3]
              table_date = extract_text_with_breaks(row.content[3])
              if !table_date.empty?
                entry.action_date = table_date
              else
                entry.action_date = action_info[:date]
              end
            else
              entry.action_date = action_info[:date]
            end

            # Check for reclamation date in the table (5th column)
            if row.content.size >= 5 && row.content[4]
              reclamation_date = extract_text_with_breaks(row.content[4])
              if !reclamation_date.empty?
                entry.reclamation_date = reclamation_date
              end
            end

            # Set trial flag if network contains "trial"
            if entry.network && entry.network.downcase.include?('trial')
              entry.trial = true
            end

            msg.entries << entry
          end
        end

        # Special case handlers for formats without tables
        if msg.entries.empty?
          # Check for non-tabular formats with identification codes
          doc.content.each_with_index do |node, index|
            if node.type == "paragraph"
              text = node.text_content.strip

              # Look for country codes in paragraph format
              if text =~ /(\d{3}\s+\d+)/i ||
                 text =~ /[Cc]ountry [Cc]ode (\d{3})/ ||
                 text =~ /(\+\d{3} \d+)/ ||
                 text =~ /[Cc]ountry [Cc]ode "(\d{3})"/ ||
                 text =~ /[Cc]ode "(\d{3})"/ ||
                 text =~ /[Cc]ode (\d{3})/ ||
                 text =~ /[Cc]odes (\d{3})/ ||
                 text =~ /^\s*(\d{3})\s*$/

                # Extract code information - expanded patterns to catch more formats
                code_match = text.match(/(\d{3})\s+(\d+)/) ||
                             text.match(/[Cc]ountry [Cc]ode (\d{3})/) ||
                             text.match(/[Cc]ountry [Cc]ode "(\d{3})"/) ||
                             text.match(/[Cc]ode "(\d{3})"/) ||
                             text.match(/[Cc]ode (\d{3})/) ||
                             text.match(/[Cc]odes (\d{3})/) ||
                             text.match(/\+(\d{3}) (\d+)/) ||
                             text.match(/^\s*(\d{3})\s*$/)

                country_code = code_match ? code_match[1] : nil
                identification_code = code_match && code_match[2] ? code_match[2] : nil

                # Look for entity name - typically at the start of a sentence
                entity_match = text.match(/that\s+([^(]+)\s*(\([^)]+\))?\s+is/) ||
                               text.match(/assigned to\s+([^(]+)\s*(\([^)]+\))/) ||
                               text.match(/previously assigned to\s+([^(]+)\s*(\([^)]+\))/)

                applicant = entity_match ? entity_match[1].strip : nil

                # Extract country/region from parentheses if available
                country_match = entity_match && entity_match[2] ? entity_match[2].match(/\(([^)]+)\)/) : nil
                network = country_match ? country_match[1].strip : nil

                # Determine action type
                action = nil
                if text =~ /granted to/i
                  action = "assigned"
                elsif text =~ /returned to spare/i || text =~ /withdrawn/i
                  action = "withdrawn"
                elsif text =~ /cancelled/i
                  action = "cancelled"
                elsif text =~ /reclaim/i
                  action = "reclaimed"
                elsif text =~ /transferred/i
                  action = "transferred"
                end

                # Extract date
                date_match = text.match(/on\s+(\d+\s+\w+\s+\d{4})/) ||
                             text.match(/(\d+\s+\w+\s+\d{4})/) ||
                             text.match(/(\d+\.\w+\.\d{4})/)

                action_date = date_match ? date_match[1] : nil

                # Extract reclamation date
                reclamation_date = nil
                if text =~ /until (\d+\.\w+\.\d{4})/i
                  reclamation_date = $1
                elsif text =~ /reclamation date.*?(\d+\.\w+\.\d{4})/i
                  reclamation_date = $1
                end

                # Special case handler for "returned to spare" and similar cases
                if text =~ /returned to spare/i && country_code
                  entry = IptnEntry.new
                  entry.cc_ic = "+#{country_code}"
                  entry.action = "withdrawn"
                  entry.action_date = date_match ? date_match[1] : nil
                  entry.applicant = "ITU-TSB" # Default applicant for returned to spare

                  # Try to extract the previous owner if mentioned
                  prev_owner_match = text.match(/previously assigned to\s+([^,\.]+)/)
                  if prev_owner_match
                    entry.formerly = prev_owner_match[1].strip
                  end

                  msg.entries << entry
                # Special case handler for eCall services
                elsif text =~ /eCall/i && (text =~ /88[123] \d+/i)
                  # Check for assigned codes in eCall paragraphs
                  code_matches = text.scan(/(\d{3} \d+)/)
                  code_matches.each do |code_match|
                    if code_match[0] =~ /^(88[123]) (\d+)$/
                      country_code = $1
                      identification_code = $2

                      # Try to extract assigned company
                      company_match = text.match(/#{Regexp.escape(code_match[0])} assigned to ([^,\.:]+)/)
                      if company_match
                        entry = IptnEntry.new
                        entry.cc_ic = "+#{country_code} #{identification_code}"
                        entry.applicant = company_match[1].strip
                        entry.action = "assigned"
                        entry.network = "eCall service"
                        msg.entries << entry
                      else
                        # For cases where the company is listed elsewhere or not directly after the code
                        entry = IptnEntry.new
                        entry.cc_ic = "+#{country_code} #{identification_code}"
                        # Try to find organization name near this code
                        org_match = text.match(/(\w+(?:\s+\w+){0,5})[^.]*#{Regexp.escape(code_match[0])}/) ||
                                    text.match(/#{Regexp.escape(code_match[0])}[^.]*?(\w+(?:\s+\w+){0,5})/)
                        if org_match
                          entry.applicant = org_match[1].strip
                        else
                          # Default to ITU-TSB if no company found
                          entry.applicant = "ITU-TSB"
                        end
                        entry.action = "assigned"
                        entry.network = "eCall service"
                        msg.entries << entry
                      end
                    end
                  end
                # Mobile Country Code and Mobile Network Code handler
                elsif text =~ /mobile country code 901/i || text =~ /MCC.*901/i
                  # Find the next table after this paragraph
                  table_index = nil
                  (index + 1...[index + 15, doc.content.size - 1].min).each do |i|
                    if doc.content[i].type == "table"
                      table_index = i
                      break
                    end
                  end

                  # If table found, extract MCC/MNC entries
                  if table_index
                    table = doc.content[table_index]
                    if table.content && table.content.size > 1
                      table.content.each_with_index do |row, row_index|
                        # Skip header row
                        next if row_index == 0
                        next if !row.content || row.content.size < 3

                        # Extract data from MCC/MNC table
                        network = extract_text_with_breaks(row.content[0])
                        code = extract_text_with_breaks(row.content[1])
                        date = extract_text_with_breaks(row.content[2])

                        if code =~ /^\s*901\s+(\d+)\s*$/
                          mnc = $1
                          entry = IptnEntry.new
                          entry.applicant = network
                          entry.network = "International Mobile Network"
                          entry.cc_ic = "MCC 901 MNC #{mnc}" # Special format for mobile networks
                          entry.action = "assigned"
                          entry.action_date = date
                          msg.entries << entry
                        end
                      end
                    end
                  end
                # Trial Identification Code handler
                elsif text =~ /identification codes for international non-commercial trials/i ||
                      text =~ /trial identification code|TIC/i && text =~ /991/
                  # Find trial info in text
                  tic_match = text.match(/(\d{3})\s+(\d{3})/) # Format like "991 001"
                  if tic_match
                    cc = tic_match[1]
                    tic = tic_match[2]

                    # Extract applicant
                    applicant_match = text.match(/assigned to ([^(\.]+)/) ||
                                     text.match(/to ([^(\.]+?) for the trial/)
                    applicant = applicant_match ? applicant_match[1].strip : "Unknown"

                    # Extract dates
                    assignment_date = nil
                    reclamation_date = nil

                    if text =~ /effective from (\d+\.\w+\.\d{4})/i
                      assignment_date = $1
                    elsif text =~ /effective date.*?(\d+\.\w+\.\d{4})/i
                      assignment_date = $1
                    end

                    if text =~ /until (\d+\.\w+\.\d{4})/i
                      reclamation_date = $1
                    elsif text =~ /reclamation date.*?(\d+\.\w+\.\d{4})/i
                      reclamation_date = $1
                    end

                    entry = IptnEntry.new
                    entry.applicant = applicant
                    entry.cc_ic = "+#{cc} #{tic}"
                    entry.action = "assigned"
                    entry.action_date = assignment_date
                    entry.reclamation_date = reclamation_date
                    entry.network = "Trial"
                    entry.trial = true
                    msg.entries << entry
                  end

                  # Also check for tables with trial codes
                  table_index = nil
                  (index + 1...[index + 15, doc.content.size - 1].min).each do |i|
                    if doc.content[i].type == "table"
                      table_index = i
                      break
                    end
                  end

                  if table_index
                    table = doc.content[table_index]
                    if table.content && table.content.size > 1
                      table.content.each_with_index do |row, row_index|
                        # Skip header row
                        next if row_index == 0
                        next if !row.content || row.content.size < 3

                        # Extract trial data from table
                        applicant = extract_text_with_breaks(row.content[0])
                        code = extract_text_with_breaks(row.content[1])
                        start_date = row.content.size > 2 ? extract_text_with_breaks(row.content[2]) : nil
                        end_date = row.content.size > 3 ? extract_text_with_breaks(row.content[3]) : nil

                        if code =~ /\+(\d{3}) (\d+)/
                          entry = IptnEntry.new
                          entry.applicant = applicant
                          entry.cc_ic = code
                          entry.action = "assigned"
                          entry.action_date = start_date
                          entry.reclamation_date = end_date
                          entry.network = "Trial"
                          entry.trial = true
                          msg.entries << entry
                        end
                      end
                    end
                  end
                # Special case for country code assignments/withdrawals
                elsif text =~ /[Cc]ountry [Cc]ode .*?(\d{3})/ ||
                      text =~ /assigned the .*?[Cc]ountry [Cc]ode .*?(\d{3})/

                  code_match = text.match(/[Cc]ountry [Cc]ode[^0-9]*(\d{3})/) ||
                               text.match(/[Cc]ountry [Cc]ode[^"]*"(\d{3})"/) ||
                               text.match(/[Cc]ountry [Cc]ode ([0-9]{3})/) ||
                               text.match(/E\.164 country code "(\d{3})"/)

                  if code_match
                    country_code = code_match[1]

                    # Extract country/organization
                    org_match = text.match(/to (?:the )?([^,\.]+)/) ||
                                text.match(/for (?:the )?([^,\.]+)/)

                    applicant = org_match ? org_match[1].strip : nil

                    # Determine action
                    action = nil
                    if text =~ /has been assigned|assigned/i
                      action = "assigned"
                    elsif text =~ /withdrawn|returned|reclaimed/i
                      action = "withdrawn"
                    end

                    # Only create entry if we have necessary info
                    if country_code && (applicant || action)
                      entry = IptnEntry.new
                      entry.cc_ic = "+#{country_code}"
                      entry.applicant = applicant
                      entry.action = action || "assigned" # Default to assigned if unclear

                      date_match = text.match(/on\s+(\d+\s+\w+\s+\d{4})/) ||
                                  text.match(/(\d+\s+\w+\s+\d{4})/) ||
                                  text.match(/(\d+\.\w+\.\d{4})/)

                      entry.action_date = date_match ? date_match[1] : nil

                      msg.entries << entry
                    end
                  end
                # Only create entry for regular cases if we have minimum required information
                elsif (country_code || identification_code) && (applicant || action)
                  entry = IptnEntry.new
                  entry.applicant = applicant
                  entry.network = network

                  if country_code && identification_code
                    entry.cc_ic = "+#{country_code} #{identification_code}"
                  elsif country_code
                    entry.cc_ic = "+#{country_code}"
                  elsif identification_code
                    entry.cc_ic = identification_code
                  end

                  entry.action = action
                  entry.action_date = action_date
                  entry.reclamation_date = reclamation_date

                  # Set trial flag if text mentions trial
                  if text.downcase.include?('trial')
                    entry.trial = true
                  end

                  msg.entries << entry
                end
              end
            end
          end
        end

        # Direct table extraction for cases where still no entries were found
        if msg.entries.empty?
          # Try to find any tables with country codes
          doc.content.each_with_index do |node, index|
            if node.type == "table" && node.content && node.content.size >= 2
              # Look at the first few paragraphs before this table to determine action type
              action_type = nil
              action_date = nil
              reclamation_date = nil

              # Check preceding paragraphs for action information
              search_start = [index - 10, 0].max
              (search_start...index).each do |i|
                if doc.content[i].type == "paragraph"
                  para_text = doc.content[i].text_content.strip
                  if para_text =~ /assigned/i
                    action_type = "assigned"
                  elsif para_text =~ /withdrawn/i
                    action_type = "withdrawn"
                  elsif para_text =~ /reclaimed/i
                    action_type = "reclaimed"
                  elsif para_text =~ /transferred/i
                    action_type = "transferred"
                  end

                  # Try to extract date
                  if para_text =~ /(\d+\.\w+\.\d{4})/i
                    action_date = $1
                  elsif para_text =~ /(\d+\s+\w+\s+\d{4})/i
                    action_date = $1
                  end

                  # Try to extract reclamation date
                  if para_text =~ /until (\d+\.\w+\.\d{4})/i
                    reclamation_date = $1
                  elsif para_text =~ /reclamation date.*?(\d+\.\w+\.\d{4})/i
                    reclamation_date = $1
                  end
                end
              end

              # Process each data row in the table
              node.content.each_with_index do |row, row_index|
                # Skip header row
                next if row_index == 0

                # Skip if row doesn't have at least 3 cells
                next if !row.content || row.content.size < 3

                # Check if any cell has a country code
                has_cc = false
                row.content.each do |cell|
                  cell_text = extract_text_with_breaks(cell)
                  if cell_text =~ /\+(88[123])/
                    has_cc = true
                    break
                  end
                end

                next unless has_cc

                entry = IptnEntry.new

                # Extract data from cells and handle hard breaks
                entry.applicant = extract_text_with_breaks(row.content[0])
                entry.network = extract_text_with_breaks(row.content[1])
                entry.cc_ic = extract_text_with_breaks(row.content[2])
                entry.action = action_type

                # Check if date is in the table (4th column) or use extracted date
                if row.content.size >= 4 && row.content[3]
                  table_date = extract_text_with_breaks(row.content[3])
                  if !table_date.empty?
                    entry.action_date = table_date
                  else
                    entry.action_date = action_date
                  end
                else
                  entry.action_date = action_date
                end

                # Check if reclamation date is in the table (5th column) or use extracted date
                if row.content.size >= 5 && row.content[4]
                  table_reclamation_date = extract_text_with_breaks(row.content[4])
                  if !table_reclamation_date.empty?
                    entry.reclamation_date = table_reclamation_date
                  else
                    entry.reclamation_date = reclamation_date
                  end
                else
                  entry.reclamation_date = reclamation_date
                end

                # Set trial flag if network contains "trial"
                if entry.network && entry.network.downcase.include?('trial')
                  entry.trial = true
                end

                msg.entries << entry
              end
            end
          end
        end

        # Extract relevant notes and filter out boilerplate content
        relevant_notes = []
        boilerplate_patterns = [
          /^__+$/,  # Underscores
          /^Note from TSB$/i,  # Note header
          /^Identification codes for international networks$/i,  # Title
          /^Identification codes for International Mobile Networks$/i,  # Alternative title
          /^Identification codes for IoT\/M2M$/i,  # IoT/M2M title
          /^Identification codes for international non-commercial trials$/i,  # Non-commercial trials title
          /^Associated with shared country code \d+ for (international networks|global mobile satellite system|iot\/m2m)/i,  # Standard intro text
          /^Following the (decisions|completion)/i,  # Common beginning of informational notes
          /^The ITU-T E\.164 country code/i,  # Common beginning for country code info
          /^At the request of the Administration/i  # Common beginning for administrative notes
        ]

        # Process paragraphs to extract notes using Prosereflect
        doc.content.each do |node|
          if node.type == "paragraph"
            # Extract text from paragraph using text_content
            text = node.text_content.strip

            # Skip if empty or just whitespace
            next if text.empty?

            # Skip if the line matches any boilerplate pattern
            should_skip = false
            boilerplate_patterns.each do |pattern|
              if text =~ pattern
                should_skip = true
                break
              end
            end

            # Add to relevant notes if not boilerplate
            relevant_notes << text unless should_skip
          end
        end

        # Set notes to empty string if there are no relevant notes or only whitespace
        notes_text = relevant_notes.join("\n").strip
        # Use strip_legacy to remove nonbreaking spaces and other special characters
        notes_text = Ituob::Helpers.strip_legacy(notes_text)
        msg.notes = notes_text.empty? ? "" : notes_text

        msg
      end

      # Helper method to get applicant for backward compatibility
      def applicant
        entries&.first&.applicant
      end

      # Helper method to get network for backward compatibility
      def network
        entries&.first&.network
      end

      # Helper method to get cc_ic for backward compatibility
      def cc_ic
        entries&.first&.cc_ic
      end

      # Helper method to get status for backward compatibility
      def status
        entries&.first&.action
      end

      # Helper method to get formerly for backward compatibility
      def formerly
        entries&.first&.formerly
      end

      # Helper method to get reclamation_date for backward compatibility
      def reclamation_date
        entries&.first&.reclamation_date
      end

      # Helper method to get trial flag for backward compatibility
      def trial
        entries&.first&.trial
      end

      # Helper method to extract text from a node, handling hard breaks
      def self.extract_text_with_breaks(node)
        return "" unless node

        # If the node has content, process it recursively
        if node.respond_to?(:content) && node.content
          text = ""
          node.content.each do |child|
            if child.type == "paragraph"
              text += extract_text_with_breaks(child) + " "
            elsif child.type == "hard_break"
              text += " " # Replace hard breaks with spaces
            elsif child.respond_to?(:text)
              text += child.text
            elsif child.respond_to?(:text_content)
              text += child.text_content
            end
          end
          return text.strip
        end

        # If the node has text, return it
        if node.respond_to?(:text)
          return node.text
        end

        ""
      end
    end
  end
end
