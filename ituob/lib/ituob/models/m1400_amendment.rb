# frozen_string_literal: true

require 'prosereflect'
require 'ituob/catalogs'
require 'ituob/support'

module Ituob
  module Models
    class M1400Amendment < Amendment
      attribute :actions, M1400Action, collection: true
      attribute :_class, :string, default: -> { self.name.split('::').last }
attribute :position, :string
attribute :entries, M1400Entry, collection: true
attribute :description, :string
attribute :caption, :string
attribute :country, :string
attribute :notes, :string, collection: true

      key_value do
        map '_class', to: :_class, render_default: true
        map 'position_on', to: :position_on
        map 'actions', to: :actions
        map 'position', to: :position
        map 'entries', to: :entries
        map 'description', to: :description
        map 'caption', to: :caption
        map 'country', to: :country
        map 'notes', to: :notes
      end

      HEADING_MARK = ' / '

      def self.normalize_heading(text)
        Ituob::Helpers.normalize_whitespace(text).split('/', -1).map(&:strip).join(HEADING_MARK)
      end

      # Split from the end so country names take linear time, even on long lines.
      def self.heading_without_slash(text)
        return if text.include?('/')

        heading, _, action_type = text.rpartition(' ')
        return unless action_type.match?(/\A[A-Z]{3}\*?\z/) &&
          Ituob::Catalogs::ActionTypes.valid?(action_type)

        country, _, iso = heading.rpartition(' ')
        return if country.empty? || !iso.match?(/\A[A-Z]{3}\z/)

        [text, country, iso, action_type]
      end

      def self.heading_with_annotation(text)
        country, mark, remainder = text.rpartition(HEADING_MARK)
        return if mark.empty? || country.empty?

        iso, action_type, note = remainder.split(' ', 3)
        return unless iso&.match?(/\A[A-Z]{3}\z/) &&
          Ituob::Catalogs::ActionTypes.valid?(action_type) && note && !note.empty?

        [text, country, iso, action_type, note]
      end

      # True when some line has a "/" followed, later on that line, by a
      # three-capital action or ISO code at its end. Same as the old
      # /^.*\/.*[A-Z]{3}$/ without its polynomial backtracking (CodeQL).
      def self.slash_heading?(text)
        text.split("\n", -1).any? do |line|
          slash = line.index('/')
          slash && slash <= line.length - 4 && line.match?(/[A-Z]{3}\z/)
        end
      end

      # "Country / ISO ... ACT" on one line: [line, country, iso, action]
      # (indexed like the MatchData it replaces) for the first such line, splitting at the last " / ISO" that leaves room for
      # the action. Same captures as the old
      # /(.*) \/ ([A-Z]{3}).+([A-Z]{3})$/, in linear time (CodeQL).
      def self.heading_with_action(text)
        text.split("\n", -1).each do |line|
          next unless line.match?(/[A-Z]{3}\z/)

          i = line.length - 10
          while i >= 0
            i = line.rindex(HEADING_MARK, i)
            break if i.nil?

            iso = line[i + 3, 3]
            return [line, line[0...i], iso, line[-3..]] if iso.match?(/\A[A-Z]{3}\z/)

            i -= 1
          end
        end
        nil
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new

        # Set the position_on if it exists
        amendment.position_on = position_on if position_on

        doc = Prosereflect::Parser.parse_document(hash)

        action = M1400Action.new
        action.entries = []
        amendment.actions << action

        country = nil
        country_code = nil

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each_with_index do |c, ci|
          next if c.nil?
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0] 
          if first_elem.is_a?(String)
            fixed_str = Ituob::Helpers.replace_legacy_space(c.join(' '))
            segs = Ituob::Helpers.split_str(fixed_str)
            fixed_str = normalize_heading(fixed_str)

            if first_elem.length < 3 
              next
            else
              if heading = heading_with_annotation(fixed_str)
                country, country_code = heading[1..2]
                action.action_type = heading[3]
                action.note = heading[4]
                action.position = "#{country} / #{country_code}"
                next
              end
              if heading = heading_without_slash(fixed_str)
                country, country_code = heading[1..2]
                action.action_type = heading[3]
                action.note = nil
                action.position = "#{country} / #{country_code}"
                next
              end
              next unless slash_heading?(fixed_str)

              action.note = segs[1]
              action.action_type = nil
              if Ituob::Catalogs::ActionTypes.valid?(fixed_str.split.last)
                if m = fixed_str.match(/[A-Z]{3}\*$/)
                  action.action_type = m[0].to_s
                elsif m = fixed_str.match(/[A-Z]{3}$/)
                  action.action_type = m[0].to_s
                end
              end
              heading = fixed_str.sub(%r{(/[[:space:]]*[A-Z]{3})[[:space:]]+[A-Z]{3}\*?\z}, '\\1').squeeze(' ').strip
              if fixed_str.match(/^P /)
                action.position = segs[0..1].join(" ")
                country, country_code = heading.sub(/\AP \S+ (?:to P \S+ )?/, '').split(' / ', 2)
              else
                action.position = heading
                country, country_code = heading.split(' / ', 2)
              end
            end

          elsif first_elem.is_a?(Array) # table
            flattened = c.flatten

            # Skip the explicit header table whose first row carries
            # "Country or area" / "Company Name" column titles.
            header_row_text = c[0]&.flatten&.join(' ').to_s
            if header_row_text.match(/Country.*\/.*ISO/) ||
               header_row_text.match(/Company Name.*Address/)
              c = c[1..]
            end

            # Iterate remaining rows (or all rows when no header was
            # detected — many M1400 amendments emit one data row per
            # table with no header at all).
            c.each do |row|
              rf = normalize_heading(row.flatten.join(''))
              rf = rf.sub(/\AP \d+ (?:to P \d+ )?/, '')
              next if rf.match(/^Country/)
              next if rf.match(/Company.Name/)
              if rf.match?(/ \/ [A-Z]{3}$/)
                country, country_code = rf.split(' / ')
                next
              end
              single_cell = row.count { |cell| !Ituob::Helpers.normalize_whitespace(cell.flatten.join).empty? } == 1
              m = single_cell ? heading_with_annotation(rf) : nil
              m ||= heading_with_action(rf)
              if !m && single_cell
                m = heading_without_slash(rf)
              end
              if m
                # This seems to actually trigger a new action
                action = M1400Action.new
                action.entries = []
                action.action_type = m[3]
                action.note = m[4] if m[4]
                country = m[1]
                country_code = m[2]
                amendment.actions << action
                next
              end
              next if rf.nil? or rf.length == 0
              segs = row.flatten
              entry = M1400Entry.new

              entry.iso_code = country_code
              entry.country_or_area = MultilingualString.new(en: country)
              entry.company_name = Ituob::Helpers.strip_legacy(row[0][0]) rescue nil
              entry.address_line_1 = Ituob::Helpers.strip_legacy(row[0][1]) rescue nil
              entry.address_line_2 = Ituob::Helpers.strip_legacy(row[0][2]) rescue nil
              entry.address_line_3 = Ituob::Helpers.strip_legacy(row[0][3]) rescue nil
              entry.carrier_code = Ituob::Helpers.strip_legacy(row[1][0]) rescue nil
              entry.contact = Ituob::Helpers.strip_legacy(row[2][0]) rescue nil
              entry.fax = Ituob::Helpers.isolate_key(row[2], 'Fax')
              entry.tel = Ituob::Helpers.isolate_key(row[2], 'Tel')
              entry.email = Ituob::Helpers.isolate_key(row[2], 'E-mail') ||
                            Ituob::Helpers.isolate_key(row[2], 'Email')

              action.entries << entry
            end
            action = M1400Action.new
            action.entries = []
            amendment.actions << action
          else
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end

        amendment.actions = amendment.actions.filter{|x| x.entries.length > 0}
        amendment
      end

    end
  end
end
