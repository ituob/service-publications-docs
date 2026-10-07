# frozen_string_literal: true

require 'prosereflect'

module Ituob
  module Models
    class E218TRCCAmendment < Amendment
      attribute :actions, E218TRCCAction, collection: true
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
        amendment.position_on = position_on if position_on
        return amendment if hash.nil? || hash == {} || !hash.is_a?(Hash)

        doc = Prosereflect::Parser.parse_document(hash)
        simplified_doc = Ituob::Helpers.dump_doc(doc)

        action = E218TRCCAction.new
        action.entries = []
        amendment.actions << action

        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0]
          if first_elem.is_a?(String)
            basestr = c.join(' ')
            fixed_str = Ituob::Helpers.replace_legacy_space(basestr)

            # Capture trailing glossary / reference notes.
            if fixed_str.match?(/^_{3,}/) || fixed_str.match?(/^See page/) ||
               fixed_str.match?(/^Notes common/) || fixed_str.match?(/^[a-z]\./)
              amendment.notes << fixed_str.strip
              next
            end

            next if first_elem.length < 3
            next unless first_elem.match(/.*Order.*ADD/) || fixed_str.match(/ADD$/)
            segs = Ituob::Helpers.split_str(basestr)

            action = E218TRCCAction.new
            action.entries = []
            action.position = segs[0..-2].join(" ")
            action.action_type = segs[-1]
            amendment.actions << action

          elsif first_elem.is_a?(Array) # table
            # Skip the header row whose first cell is "Applicant / Network".
            data_rows = c.select do |row|
              first_cell = row[0].is_a?(Array) ? row[0][0].to_s : row[0].to_s
              !first_cell.match?(/^Applicant/) &&
                !first_cell.match?(/^Country/) &&
                first_cell.strip.length > 0
            end

            data_rows.each do |row|
              cells = row.map { |cell| cell.is_a?(Array) ? cell.join(' ').strip : cell.to_s.strip }
              next if cells.all? { |x| x.empty? }

              entry = E218TRCCEntry.new
              entry.tmcc_code = cells[1] # MCC+MNC is column 2
              entry.country_or_area = MultilingualString.new(en: cells[0]) # Applicant is column 1
              entry.note = MultilingualString.new(en: cells[2]) if cells[2] # Date of assignment
              action.entries << entry
            end
          else
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end

        amendment.actions = amendment.actions.filter { |x| x.entries.length > 0 }
        amendment
      end
    end
  end
end
