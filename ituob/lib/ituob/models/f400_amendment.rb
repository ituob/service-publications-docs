# frozen_string_literal: true

require 'prosereflect'

module Ituob
  module Models
    class F400Amendment < Amendment
      attribute :actions, F400Action, collection: true
      attribute :_class, :string, default: -> { self.name.split('::').last }

      key_value do
        map '_class', to: :_class, render_default: true
        map 'position_on', to: :position_on
        map 'actions', to: :actions
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new
        # Set the position_on if it exists
        amendment.position_on = position_on if position_on
        amendment.actions = []

        doc = Prosereflect::Parser.parse_document(hash)
        simplified_doc = Ituob::Helpers.dump_doc(doc)

        action = nil

        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0]
          if first_elem.is_a?(String)
            next if first_elem.length < 2
            next unless first_elem.match(/^P/) || first_elem.match(/[A-Z]{3}$/)
            basestr = c.join('')
            segs = Ituob::Helpers.split_str(basestr)

            action = F400Action.new
            action.entries = []
            action.position = segs[0..1].join(" ")
            if m = basestr.match(/[A-Z]{3}\*$/)
              action.action_type = m[0].to_s
            elsif m = basestr.match(/[A-Z]{3}$/)
              action.action_type = m[0].to_s
            elsif segs[-1].length == 3
              action.action_type = segs[-1]
            else
              action.action_type = basestr[-3..-1]
            end

            amendment.actions << action

          elsif first_elem.is_a?(Array) # table
            # Group rows by country entry. The first row of a country
            # entry has all 9 cells populated; subsequent rows are
            # continuation (FR/EN/ES translations + multi-line address)
            # — recognized by having most middle cells empty.
            current_entry = nil
            address_lines = []
            country_names = { fr: nil, en: nil, es: nil }
            lang_idx = 0

            c.each do |row|
              next unless row.is_a?(Array)
              flat = row.map { |cell| cell.is_a?(Array) ? cell.join(' ').strip : cell.to_s.strip }

              # Header rows — skip.
              next if flat[0].to_s.match?(/^Country/) || flat[0].to_s.match?(/^MT$/)

              # Detect continuation rows: cells 1-5 are mostly empty.
              middle_empty = flat[1, 5].all? { |x| x.nil? || x.strip.empty? }

              if !middle_empty && flat[0] && !flat[0].empty?
                # New country entry — flush previous.
                if current_entry
                  current_entry.contact_address = { address_lines: address_lines.reject(&:empty?) }
                  current_entry.country_or_area = MultilingualString.new(
                    fr: country_names[:fr], en: country_names[:en], es: country_names[:es]
                  )
                  action.entries << current_entry
                end
                current_entry = F400Entry.new
                address_lines = []
                country_names = { fr: nil, en: nil, es: nil }
                lang_idx = 0

                country_names[:fr] = flat[0]
                current_entry.admd_name = flat[1]
                current_entry.country_code = flat[2]
                current_entry.helpdesk = { x400: flat[4] } if flat[4] && !flat[4].empty?
                current_entry.autoanswer = { x400: flat[5] } if flat[5] && !flat[5].empty?
                (6..8).each { |i| address_lines << flat[i] if flat[i] && !flat[i].empty? }
              elsif current_entry
                # Continuation row.
                lang_idx += 1
                if flat[0] && !flat[0].empty?
                  case lang_idx
                  when 1 then country_names[:en] = flat[0]
                  when 2 then country_names[:es] = flat[0]
                  end
                end
                (6..8).each { |i| address_lines << flat[i] if flat[i] && !flat[i].empty? }
                (1..5).each { |i| address_lines << flat[i] if flat[i] && !flat[i].empty? }
              end
            end
            # Flush the last entry.
            if current_entry
              current_entry.contact_address = { address_lines: address_lines.reject(&:empty?) }
              current_entry.country_or_area = MultilingualString.new(
                fr: country_names[:fr], en: country_names[:en], es: country_names[:es]
              )
              action.entries << current_entry
            end
          else
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end
        amendment
      end

    end
  end
end
