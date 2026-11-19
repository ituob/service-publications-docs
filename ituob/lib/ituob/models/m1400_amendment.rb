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
        Ituob::Helpers.normalize_whitespace(text).split('/', 2).map(&:strip).join(HEADING_MARK)
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
        country, mark, remainder = text.partition(HEADING_MARK)
        return if mark.empty? || country.empty?

        iso, action_type, note = remainder.split(' ', 3)
        return unless iso&.match?(/\A[A-Z]{3}\z/) &&
          Ituob::Catalogs::ActionTypes.valid?(action_type) && note && !note.empty?

        [text, country, iso, action_type, note]
      end


      COUNTRY_NAME_SPLIT = %r{/[[:space:]]*([A-Z]{3})(?=\p{Lu}\p{Ll}|[[:space:]]|\z)}
      FRENCH_NAME = /R[eé]publique|Principaut[eé]|Royaume|[EÉ]tats?\b|F[eé]d[eé]ration|\bd[’']|\b(?:du|des)\b/i
      SPANISH_NAME = /Rep[uú]blica|Principado|Principalidad|Reino|Estados?\b|Federaci[oó]n|\bdel\b/i

      # A country cell prints its name once per language, each followed by the
      # ISO code ("Name / ISO Name / ISO"); the joined text is split back into
      # one name per language. A language is read from the wording, falling back
      # to the printed English, French, Spanish order.
      def self.multilingual_country(text)
        names = text.to_s.split(COUNTRY_NAME_SPLIT).each_slice(2).map { |name, _iso| name.to_s.strip }.reject(&:empty?).uniq
        return MultilingualString.new(en: text) if names.size < 2

        langs = {}
        leftover = []
        names.each do |name|
          lang = if name.match?(SPANISH_NAME) then :es
                 elsif name.match?(FRENCH_NAME) then :fr
                 else :en
                 end
          langs.key?(lang) ? leftover << name : langs[lang] = name
        end
        leftover.each { |name| langs[%i[en fr es].find { |l| !langs.key?(l) } || :en] ||= name }
        # A glued heading ("Allemagne Germany (Federal Republic of)") carries the
        # French name's first word in front of the English name: drop it from en.
        if langs[:en] && langs[:fr]
          lead = langs[:fr][/\A\p{L}+/]
          rest = langs[:en].delete_prefix("#{lead} ")
          langs[:en] = rest if lead && rest != langs[:en] && rest.match?(/\A\p{Lu}/)
        end
        MultilingualString.new(**langs.slice(:en, :fr, :es))
      end

      # Same ISO printed again under another name (heading in one language,
      # table cell in another): keep every printed name.
      def self.accumulate_country(previous, iso, name, previous_iso)
        return name if previous.nil? || previous_iso != iso || previous.split(COUNTRY_NAME_SPLIT).map(&:strip).include?(name)

        "#{previous} / #{iso} #{name}"
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

          i = line.length - 9
          while i >= 0
            i = line.rindex(HEADING_MARK, i)
            break if i.nil?

            iso = line[i + 3, 3]
            if iso.match?(/\A[A-Z]{3}\z/)
              # Text between the ISO code and the action ("(OCPT)") is the heading caption.
              caption = line[(i + 6)...-3].to_s.strip
              return [line, line[0...i], iso, line[-3..], nil, (caption unless caption.empty?)]
            end

            i -= 1
          end
        end
        nil
      end

      # Blank carrier cells with labeled contact details continue the preceding
      # carrier in this table. Leave ambiguous unkeyed rows intact.
      def self.continuation_row?(row, entry)
        return false unless entry && !entry.carrier_code.to_s.empty?
        return false unless row.length >= 3 && row[1].all? { |text| Ituob::Helpers.strip_legacy(text).to_s.empty? }
        return false unless row.drop(3).flatten.all? { |text| Ituob::Helpers.strip_legacy(text).to_s.empty? }

        contacts = row[2].map { |text| Ituob::Helpers.strip_legacy(text) }.reject(&:empty?)
        !contacts.empty? && contacts.all? { |text| text.match?(/\A(?:Tel|Fax|E-?mail)[\s.:]/i) }
      end

      def self.append_continuation(entry, row)
        addresses = [entry.address_line_1, entry.address_line_2, entry.address_line_3]
                    .compact.reject(&:empty?)
        addresses.concat(row[0].map { |text| Ituob::Helpers.strip_legacy(text) }.reject(&:empty?))
        entry.address_line_1, entry.address_line_2 = addresses[0..1]
        entry.address_line_3 = addresses[2..].join("\n") if addresses.length >= 3

        row[2].each do |text|
          match = Ituob::Helpers.strip_legacy(text).match(/\A(Tel|Fax|E-?mail)[\s.:]*+(.*)\z/i)
          next unless match

          value = match[2].strip
          next if value.empty?

          field = case match[1].downcase
                  when 'tel' then :tel
                  when 'fax' then :fax
                  else :email
                  end
          added = field == :email ? value.split(';').map(&:strip) : [value]
          values = (Array(entry.public_send(field)) + added).reject(&:empty?).uniq
          entry.public_send("#{field}=", field == :email ? values : values.join("\n"))
        end
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
            page_heading = fixed_str.match(/\A(P \d+)(?: to P \d+)? /)
            heading_text = page_heading ? fixed_str[page_heading.end(0)..] : fixed_str

            if fixed_str.length < 3
              next
            else
              next if heading_text.match?(/\ACountry or area \//i)

              if heading = heading_with_annotation(heading_text)
                country, country_code = heading[1..2]
                action.action_type = heading[3]
                action.note = heading[4]
                action.position = page_heading ? page_heading[1] : "#{country} / #{country_code}"
                next
              end
              if heading = heading_without_slash(heading_text)
                country, country_code = heading[1..2]
                action.action_type = heading[3]
                action.note = nil
                action.position = page_heading ? page_heading[1] : "#{country} / #{country_code}"
                next
              end
              next unless slash_heading?(fixed_str)

              heading = fixed_str.sub(%r{(/[[:space:]]*[A-Z]{3})[[:space:]]+[A-Z]{3}\*?\z}, '\\1').squeeze(' ').strip
              heading_country, heading_iso = heading.sub(/\AP \S+ (?:to P \S+ )?/, '').split(' / ', 2)
              next unless heading_country && !heading_country.empty? && heading_iso&.match?(/\A[A-Z]{3}\z/)

              # Short leading fragments are part of the joined heading, not notes.
              action.note = first_elem.length < 3 ? nil : segs[1]
              action.action_type = nil
              if Ituob::Catalogs::ActionTypes.valid?(fixed_str.split.last)
                if m = fixed_str.match(/[A-Z]{3}\*$/)
                  action.action_type = m[0].to_s
                elsif m = fixed_str.match(/[A-Z]{3}$/)
                  action.action_type = m[0].to_s
                end
              end
              if fixed_str.match(/^P /)
                action.position = segs[0..1].join(" ")
              else
                action.position = heading
              end
              country, country_code = heading_country, heading_iso
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
            continuation_entry = nil
            c.each do |row|
              rf = Ituob::Helpers.replace_legacy_space(row.flatten.join('')).strip
              single_cell = row.count { |cell| !Ituob::Helpers.normalize_whitespace(cell.flatten.join).empty? } == 1
              # Blank-padded ISO-only rows were emitted as entries on main.
              # Do not broaden that shape while recovering compact slashes.
              if single_cell && (!rf.match?(%r{ / {2,}[A-Z]{3}\z}) || rf.match?(/\AP \d+ /))
                rf = normalize_heading(rf).sub(/\AP \d+ (?:to P \d+ )?/, '')
              end
              next if rf.match(/^Country/)
              next if rf.match(/Company.Name/)
              if rf.match?(/ \/ [A-Z]{3}$/)
                continuation_entry = nil
                heading_country, heading_iso = rf.split(' / ')
                if heading_iso != country_code
                  action = M1400Action.new
                  action.entries = []
                  amendment.actions << action
                end
                country = accumulate_country(country, heading_iso, heading_country, country_code)
                country_code = heading_iso
                next
              end
              m = single_cell ? heading_with_annotation(rf) : nil
              m ||= heading_with_action(rf)
              if !m && single_cell
                m = heading_without_slash(rf)
              end
              if m
                continuation_entry = nil
                # This seems to actually trigger a new action
                action = M1400Action.new
                action.entries = []
                action.action_type = m[3]
                action.note = m[4] if m[4]
                action.caption = m[5] if m[5]
                country = m[1]
                country_code = m[2]
                amendment.actions << action
                next
              end
              next if rf.nil? or rf.length == 0
              if continuation_row?(row, continuation_entry)
                append_continuation(continuation_entry, row)
                next
              end
              segs = row.flatten
              entry = M1400Entry.new

              entry.iso_code = country_code
              entry.country_or_area = multilingual_country(country)
              entry.company_name = Ituob::Helpers.strip_legacy(row[0][0]) rescue nil
              entry.address_line_1 = Ituob::Helpers.strip_legacy(row[0][1]) rescue nil
              entry.address_line_2 = Ituob::Helpers.strip_legacy(row[0][2]) rescue nil
              address_tail = Array(row[0])[3..]
              if address_tail
                entry.address_line_3 = address_tail.map { |line| Ituob::Helpers.strip_legacy(line) }.reject(&:empty?).join(' ')
              end
              entry.carrier_code = Ituob::Helpers.strip_legacy(row[1][0]) rescue nil
              contact_text = Ituob::Helpers.replace_legacy_space(Array(row[2]).join('; '))
              contact = contact_text.split(Ituob::Helpers::CONTACT_LABEL, 2).first.to_s.strip
              # Search backwards once instead of retrying a trailing run at every separator.
              contact = contact[0, (contact.rindex(/[^;\s—]/) || -1) + 1]
              entry.contact = contact.empty? ? Ituob::Helpers.strip_legacy(row[2]&.first) : contact
              entry.fax = Ituob::Helpers.isolate_key(row[2], 'Fax')
              entry.tel = Ituob::Helpers.isolate_key(row[2], 'Tel')
              email = Ituob::Helpers.isolate_key(row[2], 'E-mail')
              entry.email = email.split(';').map(&:strip).reject(&:empty?) if email

              action.entries << entry
              continuation_entry = entry
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
