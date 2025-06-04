# frozen_string_literal: true

require_relative 'multilingual_string'
require_relative 'entry'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class E118Entry < Entry
      DATASET_CODE = '1161-E.118'

      attribute :country_or_area, MultilingualString
      attribute :company_name, :string
      attribute :company_address_1, :string
      attribute :company_address_2, :string
      attribute :company_address_3, :string
      attribute :contact, :string
      attribute :contact_address_1, :string
      attribute :contact_address_2, :string
      attribute :contact_address_3, :string
      attribute :contact_address_4, :string
      attribute :contact_address_5, :string
      attribute :contact_address_6, :string
      attribute :tel, :string, collection: true
      attribute :fax, :string, collection: true
      attribute :email, :string, collection: true
      attribute :issue_id_number, :string
      attribute :effective_date, :string

      def self.parse(prosemirror_row)
        entry = new

        # puts "Parsing row: #{row.inspect}"
        # puts "Parsing row text: #{row.text_content.inspect}"

        # Extract country/area
        if prosemirror_row.cells.size > 0
          entry.country_or_area = MultilingualString.new(en: prosemirror_row.cells[0].text_content.strip)
        end

        # Extract company info
        if prosemirror_row.cells.size > 1
          lines = prosemirror_row.cells[1].lines

          entry.company_name = lines[0] if lines.size > 0
          (1..3).each do |i|
            if lines.size > i && lines[i]
              entry.send("company_address_#{i}=", lines[i].gsub(/[[:space:]]/, ' ').strip)
            end
          end
        end

        # Extract issuer identifier number
        if prosemirror_row.cells.size > 2
          entry.issue_id_number = prosemirror_row.cells[2].text_content.gsub(/[[:space:]]+/, ' ').strip
        end

        # Extract contact info
        if prosemirror_row.cells.size > 3
          lines = prosemirror_row.cells[3].lines
          contact_lines = []
          tel_fax_email_lines = []
          contact_info_started = false

          lines.each do |line|
            # More comprehensive pattern matching for contact info detection
            if !contact_info_started && (
              line =~ /^(Tel|Tél|Cell|Mobile)(?:\.|:|\s)/i ||
              line =~ /^Fax\s*(?:\.|:)/i ||
              line =~ /^E-?mail\s*(?:\.|:)/i ||
              line =~ /^:/ ||
              line.include?('@')
            )
              contact_info_started = true
            end

            if contact_info_started
              tel_fax_email_lines << line
            else
              contact_lines << line
            end
          end

          entry.contact = Ituob::Helpers.strip_legacy(contact_lines[0]) || nil
          (1..6).each do |i|
            if contact_lines.size > i && contact_lines[i]
              entry.send("contact_address_#{i}=", contact_lines[i].gsub(/[[:space:]]/, ' ').strip)
            end
          end

          # Extract tel, fax, email from remaining lines
          tel = []
          fax = []
          email = []

          tel_fax_email_lines.each do |line|
            # Handle various phone number formats (Tel:, Tel.:, Tél:, Cell:, etc.)
            if line =~ /^(Tel|Tél|Cell|Mobile)(?:\.|:|\s)/i || line =~ /^:/
              # Handle all variations including "Tel: +1234", "Tél: +1234", "Tel +1234", "Tel : +1234" or just ": +1234"
              text = line.gsub(/^(?:(Tel|Tél|Cell|Mobile)(?:\.|:|\s)?|:)[[:space:]]*/, '').strip
              tel << text unless text.empty?

            elsif line =~ /^Fax\s*(?:\.|:)/i
              text = line.gsub(/^Fax(?:\.|:)[[:space:]]*/, '').strip
              fax << text unless text.empty?

            elsif line =~ /^E-?mail\s*(?:\.|:)/i || line.include?('@')
              # Handle multiple email addresses on a single line
              if line.count('@') > 1
                # Split by whitespace and filter for valid email addresses
                emails = line.sub(/^E-?mail(?:\.|:)[[:space:]]*/, '').split(/\s+/).select { |e| e.include?('@') }
                email.concat(emails)
              else
                text = line.sub(/^E-?mail(?:\.|:)[[:space:]]*/, '').strip
                email << text unless text.empty?
              end
            end
          end

          # Also check contact_address fields for misclassified phone numbers or emails
          (1..6).each do |i|
            addr_field = entry.send("contact_address_#{i}")
            next unless addr_field

            # Check for phone numbers - handles various formats
            if addr_field =~ /^(Tel|Tél|Cell|Mobile)(?:\.|:|\s)/i || addr_field =~ /^:/
              # Handle cases like "Tel: +1234", "Tél: +1234", "Tel : +1234", "Tel +1234", or simply ": +1234"
              text = addr_field.gsub(/^(?:(Tel|Tél|Cell|Mobile)(?:\.|:|\s)?|:)[[:space:]]*/, '').strip
              tel << text
              entry.send("contact_address_#{i}=", nil) # Clear the field as it's been moved to tel
            elsif addr_field =~ /^Fax(?:\.|:)/i
              text = addr_field.gsub(/^Fax(?:\.|:)[[:space:]]*/, '').strip
              fax << text
              entry.send("contact_address_#{i}=", nil) # Clear the field
            elsif addr_field.include?('@')
              # Handle multiple email addresses
              if addr_field.count('@') > 1
                emails = addr_field.split(/\s+/).select { |e| e.include?('@') }
                email.concat(emails)
              else
                email << addr_field.strip
              end
              entry.send("contact_address_#{i}=", nil) # Clear the field
            end
          end

          # Clean telephone numbers before setting them (remove leading colons, normalize spaces)
          tel = tel.map do |t|
            # Remove leading colon and normalize spaces
            t.sub(/^:/, '').strip
          end unless tel.empty?

          entry.tel = tel unless tel.empty?
          entry.fax = fax unless fax.empty?
          entry.email = email unless email.empty?
        end

        # - type: table_cell
        #   attrs:
        #     colspan: 1
        #     rowspan: 1
        #     colwidth: null
        #   content:
        #   - type: paragraph
        #     content:
        #       - type: text
        #         text: 1.II.2012
        if prosemirror_row.cells.size > 4
          entry.effective_date = prosemirror_row.cells[4].text_content.gsub(/[[:space:]]/, ' ').strip
        end

        entry
      end
    end
  end
end
