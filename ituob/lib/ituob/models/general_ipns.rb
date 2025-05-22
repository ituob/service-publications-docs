require 'lutaml/model'
require_relative 'general_message'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class GeneralIpns < GeneralMessage
      attribute :network, :string
      attribute :mcc_mnc, :string
      attribute :date_of_assignment, :string
      attribute :notes, :string

      key_value do
        map 'type', to: :type
        map 'network', to: :network
        map 'mcc_mnc', to: :mcc_mnc
        map 'date_of_assignment', to: :date_of_assignment
        map 'notes', to: :notes
      end

      def self.parse(data)
        msg = new
        msg.type = 'ipns'

        # If data is already in the expected format with type: ipns
        if data.is_a?(Hash) && data['type'] == 'ipns'
          msg.network = data['network'] if data['network']
          msg.mcc_mnc = data['mcc_mnc'] if data['mcc_mnc']
          msg.date_of_assignment = data['date_of_assignment'] if data['date_of_assignment']
          msg.notes = data['notes'] if data['notes']
          return msg
        end

        # Otherwise, parse from ProseMirror format
        notes = []
        network = nil
        mcc_mnc = nil
        date_of_assignment = nil

        # Parse the ProseMirror document using Prosereflect
        doc = Prosereflect::Parser.parse_document(data)

        # Extract table data from the ProseMirror document
        doc.content.each do |node|
          if node.type == "table" && node.content && node.content.size >= 2
            # First row is header
            header_row = node.content[0]
            # Second row is data
            data_row = node.content[1]

            if header_row && data_row &&
               header_row.content && data_row.content &&
               header_row.content.size >= 2 && data_row.content.size >= 2

              # Extract network from first cell using text_content
              network = data_row.content[0].text_content.strip

              # Extract MCC/MNC from second cell using text_content
              mcc_mnc = data_row.content[1].text_content.strip

              # Extract date of assignment from third cell if it exists
              if header_row.content.size >= 3 && data_row.content.size >= 3
                date_of_assignment = data_row.content[2].text_content.strip
              end
            end
          end
        end

        # Extract relevant notes and filter out boilerplate content
        relevant_notes = []
        boilerplate_patterns = [
          /^__+$/,  # Underscores
          /^\*\s+MCC:/i,  # MCC footnote
          /^\*\*\s+MNC:/i,  # MNC footnote
          /^Note from TSB$/i,  # Note header
          /^Identification codes for International Mobile Networks$/i,  # Title
          /^Associated with shared mobile country code \d+ \(MCC\)/i,  # Standard intro text
          /MCC: Mobile Country Code/i,  # MCC explanation
          /MNC: Mobile Network Code/i   # MNC explanation
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

        msg.network = network
        msg.mcc_mnc = mcc_mnc
        msg.date_of_assignment = date_of_assignment
        # Set notes to empty string if there are no relevant notes or only whitespace
        notes_text = relevant_notes.join("\n").strip
        # Use strip_legacy to remove nonbreaking spaces and other special characters
        notes_text = Ituob::Helpers.strip_legacy(notes_text)
        msg.notes = notes_text.empty? ? "" : notes_text
        msg
      end

    end

  end
end
