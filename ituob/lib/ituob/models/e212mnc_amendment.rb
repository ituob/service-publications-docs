# frozen_string_literal: true

require 'prosereflect'

module Ituob
  module Models
    class E212MNCAmendment < Amendment
      attribute :actions, E212MNCAction, collection: true
      attribute :notes, :string, collection: true
      attribute :_class, :string, default: -> { self.name.split('::').last }

      key_value do
        map '_class', to: :_class, render_default: true
        map 'position_on', to: :position_on
        map 'actions', to: :actions
        map 'notes', to: :notes
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new

        # Set the position_on if it exists
        amendment.position_on = position_on if position_on

        # Bail out gracefully on empty-content amendments.
        return amendment if hash.nil? || hash == {} || !hash.is_a?(Hash)

        doc = Prosereflect::Parser.parse_document(hash)

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        action = E212MNCAction.new
        action.entries = []
        amendment.actions << action
        amendment.notes = []

        # Capture trilingual glossary notes (MCC/MNC definitions).
        simplified_doc.each do |c|
          next unless c[0].is_a?(String)
          text = Ituob::Helpers.replace_legacy_space(c.join(' ')).strip
          if (text.match?(/MCC:/) || text.match?(/MNC:/)) && !text.empty?
            amendment.notes << text
          end
        end

        last_country = nil
        editor_country = nil

        simplified_doc.each_with_index do |c, ci|
          next if c.nil?
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0]
          if first_elem.is_a?(String)
            fixed_str = Ituob::Helpers.replace_legacy_space(c.join(' '))
            stripped = fixed_str.strip

            # Handle continuation paragraphs: "334 010 Network..." that
            # extend the previous country's entry list. These may have
            # leading whitespace that makes first_elem look too short.
            if action && stripped.match(/^\d{3}\s+\d+/)
              fixed_segs = Ituob::Helpers.split_str_normal(stripped)
              if fixed_segs[0]&.match?(/^\d{3}$/) && fixed_segs[1]&.match?(/^\d+/)
                mcc_mnc = fixed_segs[0..1].join(' ')
                networks = fixed_segs[2..]&.join(' ')
                entry = E212MNCEntry.new
                entry.country_or_area = MultilingualString.new(en: last_country) if last_country
                entry.mcc_mnc_codes = mcc_mnc
                entry.networks = networks if networks && !networks.empty?
                action.entries << entry
                next
              end
            end

            if first_elem.length < 3
              next
            elsif fixed_str.match(/^[onpq] /)
              action.note = (action.note || "") + fixed_str
            else
              next if !(first_elem.match(/^P/) || first_elem.match(/Note /))

              basestr = c.join('')
              segs = Ituob::Helpers.split_str(basestr)

              action.note = segs[1]
              action.position = segs[0..1].join(" ")
              if m = basestr.match(/[A-Z]{3}\*?$/)
                action.action_type = m[0].to_s
              elsif m = basestr.match(/[A-Z]{3}$/)
                action.action_type = m[0].to_s
              elsif segs[-1].length == 3
                action.action_type = segs[-1]
              else
                action.action_type = basestr[-3..-1]
              end

              # Paragraph-based entries: some E212_MNC amendments have
              # space-aligned text (no tables). Extract entries from
              # the paragraph text. Format: "P xx Country ACTION MCC MCC Network..."
              fixed_segs = Ituob::Helpers.split_str_normal(fixed_str)
              action_idx = fixed_segs.index { |s| s.match?(/^(ADD|SUP|LIR|REP)$/) }
              if action_idx
                # The printed country (between position and action
                # keyword) applies to this line's entry AND to any
                # continuation paragraphs that follow ("NNN NN Network").
                country = fixed_segs[2...action_idx]&.join(' ')
                last_country = country if country && !country.empty?
                if action_idx + 1 < fixed_segs.length
                  rest = fixed_segs[(action_idx + 1)..]
                  # MCC+MNC is typically "NNN NN" (3 digits + space + 2+ digits)
                  mcc_mnc = rest[0..1].join(' ')
                  networks = rest[2..]&.join(' ')
                  if mcc_mnc.match?(/^\d{3}\s\d+/)
                    entry = E212MNCEntry.new
                    entry.country_or_area = MultilingualString.new(en: country) if country && !country.empty?
                    entry.mcc_mnc_codes = mcc_mnc
                    entry.networks = networks if networks && !networks.empty?
                    action.entries << entry
                  end
                end
              end
            end

            # Check for continuation paragraphs (just MCC+MNC + network,
            # no action header). These extend the previous country's
            # entry list.
            if action && action.entries.any? && !first_elem.match(/^P/)
              fixed_segs = Ituob::Helpers.split_str_normal(fixed_str)
              if fixed_segs[0]&.match?(/^\d{3}$/) && fixed_segs[1]&.match?(/^\d+/)
                mcc_mnc = fixed_segs[0..1].join(' ')
                networks = fixed_segs[2..]&.join(' ')
                entry = E212MNCEntry.new
                entry.country_or_area = MultilingualString.new(en: last_country) if last_country
                entry.mcc_mnc_codes = mcc_mnc
                entry.networks = networks if networks && !networks.empty?
                action.entries << entry
              end
            end

          elsif first_elem.is_a?(Array) # table
            c[1..].each do |row|
              segs = row.flatten

              if row.length == 1
                # Editor layout: single-cell "«country»\u00a0\u00a0 ACTION"
                # rows carry the action for the entry rows that follow;
                # other single-cell rows are titles — skip.
                text = segs[0].to_s
                if (m = text.match(/\A(.*?)[\u00a0 ]+(ADD|SUP|REP|LIR|MOD|DEL)\z/)) && !m[1].strip.empty?
                  action = E212MNCAction.new
                  action.action_type = m[2]
                  action.entries = []
                  amendment.actions << action
                  editor_country = Ituob::Helpers.replace_legacy_space(m[1]).strip
                end
              elsif row.length == 3
                if row[1].count > 1
                  row[1].zip(row[2]).each do |r|
                    entry = E212MNCEntry.new
                    entry.country_or_area = MultilingualString.new(en: row[0])
                    entry.mcc_mnc_codes = r[0]
                    entry.networks  = r[1]
                    action.entries << entry
                  end
                else
                  entry = E212MNCEntry.new
                  entry.country_or_area = MultilingualString.new(en: segs[0])
                  entry.mcc_mnc_codes = segs[1]
                  entry.networks = segs[2]
                  action.entries << entry
                end
              elsif row.length == 2
                # Data rows are code/networks pairs; the header row
                # ("MCC + MNC" / "Operator / Network") is not data.
                next unless segs[0].to_s.match?(/\A\d{3}(?:[\u00a0 ]+\d+)?\z/)

                entry = E212MNCEntry.new
                entry.country_or_area = MultilingualString.new(en: editor_country) if editor_country && !editor_country.empty?
                entry.mcc_mnc_codes = segs[0]
                entry.networks = segs[1]
                action.entries << entry
              elsif row.length >= 4
                # 4+ column rows: country/code/range/networks or
                # code/dec/range/networks. Map first 4 cells.
                entry = E212MNCEntry.new
                entry.country_or_area = MultilingualString.new(en: segs[0]) unless segs[0].to_s.strip.empty?
                entry.mcc_mnc_codes = segs[1]
                entry.range = segs[2]
                entry.networks = segs[3]
                action.entries << entry
              end
            end
          else
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end

        # The per-table action rollover leaves a typeless, noteless
        # action with no entries behind; it is not a published
        # announcement.
        amendment.actions.reject! do |a|
          a.entries.empty? && a.action_type.nil? && a.note.nil? &&
            (a.notes.nil? || a.notes.empty?)
        end

        amendment
      end
    end
  end
end
