# frozen_string_literal: true

require 'prosereflect'

module Ituob
  module Models
    class E164CCAmendment < Amendment
      attribute :actions, E164CCAction, collection: true
      attribute :_class, :string, default: -> { self.name.split('::').last }
attribute :position, :string
attribute :entries, E164CCEntry, collection: true
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

      # Walk state for one document parse — the active action. Held in
      # a plain object so parse keeps no class-level state (reentrant).
      class State
        attr_accessor :action, :previous_action
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new

        # Set the position_on if it exists
        amendment.position_on = position_on if position_on

        doc = Prosereflect::Parser.parse_document(hash)

        state = State.new
        state.action = E164CCAction.new
        state.action.entries = []
        amendment.actions << state.action

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        definitions = Hash.new { |hash, key| hash[key] = [] }
        entries = []
        simplified_doc.each_with_index do |c, index|
          next if c.nil?
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0]
          if first_elem.is_a?(String)
            fixed_str = Ituob::Helpers.normalize_whitespace(c.join(' '))

            if (date = fixed_str.match(/\A(\*+)\s+(?:As from\s+)?(\d{1,2}\s+[A-Za-z]+\s+\d{4})\z/i))
              amendment.notes << fixed_str
              previous = state.previous_action
              if previous && previous.position.to_s[/\*+\z/] == date[1]
                previous.entries.each { |entry| entry.effective_date = date[2] }
              end
            elsif (definition = fixed_str.match(/\A([a-z])\s+(.+)\z/))
              definitions[definition[1]] << [index, fixed_str]
              amendment.notes << fixed_str
            elsif fixed_str.match?(/\A(?:P\s*\d+|Note\s|country code\s|(?:ADD|SUP|REP|LIR)\s+notes?\s)/i)
              amendment.notes << fixed_str if fixed_str.match?(/\A(?:ADD|SUP|REP|LIR)\s+notes?\s+[a-z]\b/i)
              state.action.position = fixed_str
              state.action.note = fixed_str[/Note\s+([a-z])\)/i, 1]
              state.action.action_type = fixed_str[/\b(ADD|SUP|REP|LIR|MOD|DEL)\b/, 1]
            end

          elsif first_elem.is_a?(Array) # table
            trial_table = c[0].flatten.join(' ').include?('Trial Identification Code')
            c[1..].each do |row|
              next unless row.length >= 3
              segs = row.map { |cell| cell.is_a?(Array) ? cell.join(' ').strip : cell.to_s.strip }
              entry = E164CCEntry.new
              if row.length == 3 && segs[0].match?(/\A\d{3}\z/)
                entry.country_code = segs[0]
                entry.country_area_or_service = MultilingualString.new(en: segs[1])
                entry.notes = segs[2].split(/[,\p{Space}]+/).reject(&:empty?)
              elsif row.length == 3
                entry.network = segs[0]
                entry.cc_ic = segs[1]
                entry.status = segs[2]
                entry.notes << state.action.note if state.action.note
              elsif trial_table
                entry.applicant = segs[0]
                entry.cc_ic = segs[1]
                entry.effective_date = segs[2]
                entry.reclamation_date = segs[3]
                entry.notes << 's'
              else
                entry.applicant = segs[0]
                entry.network = segs[1]
                entry.cc_ic = segs[2]
                entry.status = segs[3]
                entry.action_date = segs[4] if segs[4] && !segs[4].empty?
                entry.reclamation_date = segs[5] if segs[5] && !segs[5].empty?
                if entry.applicant.match(/Formerly/)
                  entry.applicant = segs[0].match(/([^(]*)/).to_s.strip
                  entry.formerly = segs[0].match(/\((.*)\)/)[1].gsub('Formerly ','').strip
                end
                entry.notes << state.action.note if state.action.note
              end
              state.action.entries << entry
              entries << [index, entry]
            end
            state.previous_action = state.action
            state.action = E164CCAction.new
            state.action.entries = []
            amendment.actions << state.action
          else
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end

        entries.each do |index, entry|
          entry.notes.concat(entry.notes.filter_map do |key|
            candidates = definitions[key]
            # Country rows define their letters below the table; network
            # tables announce their letter above it, sometimes repeatedly.
            before, after = candidates.partition { |position, _| position < index }
            definition = entry.country_code ? (after.first || before.last) : (before.last || after.first)
            definition&.last
          end)
        end

        amendment
      end

    end
  end
end
