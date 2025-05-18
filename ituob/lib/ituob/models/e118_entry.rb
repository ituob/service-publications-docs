# frozen_string_literal: true

require_relative 'multilingual_string'
require_relative 'entry'
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
            if !contact_info_started && (line.start_with?('Tel:') || line.start_with?('Fax:') || line.start_with?('E-mail:') || line.include?('@'))
              contact_info_started = true
            end

            if contact_info_started
              tel_fax_email_lines << line
            else
              contact_lines << line
            end
          end

          entry.contact = contact_lines[0].strip if contact_lines.size > 0 && contact_lines[0]
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
            if line.start_with?('Tel:')
              tel << line.gsub(/^Tel:[[:space:]]*/, '').strip
            elsif line.start_with?('Fax:')
              fax << line.gsub(/^Fax:[[:space:]]*/, '').strip
            elsif line.start_with?('E-mail:') || line.include?('@')
              email << line.sub(/^E-?mail:[[:space:]]*/, '').strip
            end
          end

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
