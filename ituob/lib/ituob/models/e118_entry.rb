# frozen_string_literal: true

require 'prosereflect'

module Ituob
  module Models
    class E118Entry < Entry
      DATASET_CODE = '1161-E.118'

      attribute :country_or_area, MultilingualString
      attribute :company_name, :string
      # Every printed line after the company name / contact name, in print
      # order. The printed cell has no fixed number of address lines (a
      # postal code and city can be a fourth), so nothing caps the list.
      attribute :company_address, :string, collection: true
      attribute :contact, :string
      attribute :contact_address, :string, collection: true
      attribute :tel, :string, collection: true
      attribute :fax, :string, collection: true
      attribute :email, :string, collection: true
      attribute :issue_id_number, :string
      attribute :effective_date, :string

      def self.parse(prosemirror_row)
        entry = new

        # Extract country/area
        if prosemirror_row.cells.size > 0
          entry.country_or_area = MultilingualString.new(en: prosemirror_row.cells[0].text_content.strip)
        end

        # Extract company info
        if prosemirror_row.cells.size > 1
          lines = prosemirror_row.cells[1].lines

          entry.company_name = lines[0] if lines.size > 0
          address = lines.drop(1).compact.map { |line| line.gsub(/[[:space:]]/, ' ').strip }.reject(&:empty?)
          entry.company_address = address unless address.empty?
        end

        # Extract issuer identifier number
        if prosemirror_row.cells.size > 2
          entry.issue_id_number = prosemirror_row.cells[2].text_content.gsub(/[[:space:]]+/, ' ').strip
        end

        # Extract contact info
        if prosemirror_row.cells.size > 3
          lines = prosemirror_row.cells[3].content.to_a.flat_map do |node|
            case node
            when Prosereflect::Paragraph
              node.text_content.split("\n")
            when Prosereflect::Table
              node.rows.map { |row| row.cells.map { |cell| cell.lines.join(' ') }.join(' ') }
            else
              node.type == 'code_block' ? node.text_content.split("\n") : []
            end
          end.flat_map do |line|
            normalized = line.gsub(/[\p{Space}\p{Zs}]/, ' ').strip
            # Some source rows print a contact label after its address on the
            # same line. Split at the label so the address prefix survives.
            normalized.split(/(?<=\S) +(?=(?:(?:Tel|Tél|Cell|Mobile|Fax|E-?mail)\s*(?:\.|:)|Fax\s+(?=\+?\d)))/i)
          end.reject(&:empty?)
          telephone_label = /\A(?:(?:Tel|Tél|Cell)(?:\s*[.:]|\s)|Mobile(?:\s*[.:]|\s+(?=\+?\d)))/i
          fax_label = /\AFax(?:\s*[.:]|\s+(?=\+?\d))/i
          contact_lines = []
          tel_fax_email_lines = []
          contact_info_started = false

          lines.each do |line|
            if !contact_info_started && (
              line.match?(telephone_label) ||
              line.match?(fax_label) ||
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
          contact_address = contact_lines.drop(1).compact.map { |line| line.gsub(/[[:space:]]/, ' ').strip }.reject(&:empty?)

          tel = []
          fax = []
          email = []

          last_label = nil
          tel_fax_email_lines.each do |line|
            continuation = line.gsub(/[[:space:]]/, '')
            # A telephone or fax list wrapped after "/" ("+358 294 440 500/" /
            # "+358 40 8668 582") keeps its second number on the next line.
            numbers = last_label == :fax ? fax : tel
            if %i[tel fax].include?(last_label) && numbers.last&.end_with?('/') &&
               line !~ /^(Tel|Tél|Cell|Mobile|Fax|E-?mail)(?:\.|:|\s)/i && line !~ /^:/ &&
               line.gsub(/[[:space:]]+/, ' ').strip.match?(%r{\A\+?\d[\d ()./-]*\z})
              numbers[-1] = "#{numbers.last} #{line.gsub(/[[:space:]]+/, ' ').strip}"
              next
            end

            # Unlabelled international numbers continue the preceding phone/fax list.
            if %i[tel fax].include?(last_label) && line.match?(/\A\+\s*\d[\d ().;\/+\-]*(?:\([A-Za-z]+\))?\z/)
              numbers.concat(split_contact_numbers(line))
              next
            end

            # A printed e-mail address wrapped after its "@" continues on the
            # next line ("jerry@" / "marathontelecom.net"): join the two.
            if email.last&.end_with?('@') && line !~ /^(Tel|Tél|Cell|Mobile|Fax|E-?mail)(?:\.|:|\s)/i && line !~ /^:/ &&
               continuation.match?(/\A[^@:]+\.[[:alpha:]]+\z/)
              email[-1] = "#{email.last}#{continuation}"
              next
            end

            if line.match?(telephone_label) || line =~ /^:/
              text = line.sub(telephone_label, '').sub(/^:/, '').strip
              tel.concat(split_contact_numbers(text))
              last_label = :tel

            elsif line.match?(fax_label)
              text = line.sub(fax_label, '').strip.sub(/^:/, '').strip
              fax.concat(split_contact_numbers(text))
              last_label = :fax

            elsif line =~ /^E-?mail\s*(?:\.|:)/i || line.include?('@')
              last_label = :email
              if line.count('@') > 1
                emails = line.sub(/^E-?mail\s*(?:\.|:)[[:space:]]*/i, '').split(/\s+/).select { |e| e.include?('@') }
                email.concat(emails)
              else
                text = line.sub(/^E-?mail\s*(?:\.|:)[[:space:]]*/i, '').strip
                email << text unless text.empty?
              end
            end
          end

          # Sweep contact address lines for misclassified phone numbers/emails.
          contact_address = contact_address.reject do |addr_field|
            if addr_field.match?(telephone_label) || addr_field =~ /^:/
              tel << addr_field.sub(telephone_label, '').sub(/^:/, '').strip
            elsif addr_field.match?(fax_label)
              fax << addr_field.sub(fax_label, '').sub(/^:/, '').strip
            elsif addr_field.include?('@')
              if addr_field.count('@') > 1
                email.concat(addr_field.split(/\s+/).select { |e| e.include?('@') })
              else
                email << addr_field.strip
              end
            else
              false
            end
          end
          entry.contact_address = contact_address unless contact_address.empty?

          tel = tel.map { |t| t.sub(/^:/, '').strip } unless tel.empty?

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

      def self.split_contact_numbers(text)
        text.split(/\s*;\s*|(?<=[\d)])\s+(?=\+\s*\d)/).map(&:strip).reject(&:empty?)
      end
      private_class_method :split_contact_numbers
    end
  end
end
