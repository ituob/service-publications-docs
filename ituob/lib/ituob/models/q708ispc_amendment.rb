# frozen_string_literal: true

require 'prosereflect'

module Ituob
  module Models
    class Q708ISPCAmendment < Amendment
      attribute :actions, Q708ISPCAction, collection: true
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

        # Bail out gracefully on empty-content amendments (e.g. the
        # source declared an amendment but provided no payload).
        # Caller checks +actions.any?+ before writing output.
        return amendment if hash.nil? || hash == {} || !hash.is_a?(Hash)

        doc = Prosereflect::Parser.parse_document(hash)

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        amendment.actions = []
        amendment.notes = []

        country = nil
        action = nil

        simplified_doc.each_with_index do |c, ci|
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0]
          if first_elem.is_a?(String)
            basestr = c.join('')
            fixed_str = Ituob::Helpers.replace_legacy_space(basestr)
            stripped = fixed_str.strip

            # Capture trailing glossary notes (ISPC: EN, Codes de: FR,
            # Códigos de: ES). Strip first since FR/ES lines have
            # leading whitespace from the source ProseMirror doc.
            if stripped.match?(/^[A-Z]{2,5}:/) ||
               stripped.match?(/^Codes de/) ||
               stripped.match?(/^Códigos de/) ||
               stripped.match?(/^Códicos de/) ||
               stripped.match?(/^[a-z]\. /) ||
               stripped.match?(/^_{3,}/)
              amendment.notes << stripped unless stripped.empty?
              next
            end

            next if first_elem.length < 3
            # Trailing-keyword check on the stripped form — printed
            # lines carry trailing padding spaces.
            next unless fixed_str.match(/^P /) || stripped.match(/[A-Z]{3}$/)
            segs = Ituob::Helpers.split_str(basestr)

            action = Q708ISPCAction.new
            action.entries = []
            action.position = segs[0..1].join(" ")
            country = segs[2]
            if match = basestr.match(/([A-Z]{3})\*?$/)
              action.action_type = match[1]
            end
            amendment.actions << action

          elsif first_elem.is_a?(Array) # table

            c.each do |r|
              rf = r.flatten
              next if rf.count == 0
              # Blank rows (all cells empty).
              next if Ituob::Helpers.strip_legacy(rf.join(' ')).empty?
              # Header rows ("Country/Geographical Area", "ISPC/DEC",
              # "Company Name/Address") — tolerate leading padding and
              # non-breaking spaces (replace_legacy_space before strip).
              next if Ituob::Helpers.strip_legacy(rf.join(' ')).match?(/\A(Country|ISPC|Company)/)
              basestr = rf.join(' ')
              fixed_str = Ituob::Helpers.replace_legacy_space(basestr)
              segs = Ituob::Helpers.split_str_normal(fixed_str)
              single_space_str = segs.join(' ')

              matched = true

              # "P 100 to P 101 Hong Kong, China ADD" 
              if match = single_space_str.match(/^(P [0-9]+ to P [0-9]+) (.+) (ADD|LIR|SUP)\*?$/)
                action = Q708ISPCAction.new 
                action.entries = []
                action.position = match[1].strip
                country = match[2].strip
                if match2 = basestr.match(/([A-Z]{3})\*?$/)
                  action.action_type = match2[3]
                end
                amendment.actions << action 

              # "P 100 to P 101 Belgium"
              elsif match = fixed_str.match(/^(P [0-9]+ to P [0-9]+) (.*)$/)
                action = Q708ISPCAction.new 
                action.entries = []
                action.position = match[1].strip
                country = match[2].strip
                # action.action_type = match2[3]
                amendment.actions << action 

              #  "P  3     Afghanistan    ADD"  
              elsif fixed_str.match(/^P /) && fixed_str.match(/(ADD|LIR|SUP)$/) 
                action = Q708ISPCAction.new 
                action.entries = []
                action.position = segs[0..1].join(" ")
                if segs.length > 4
                  country = segs[2..-2].join(' ')
                else
                  country = segs[2]
                end
                if match = basestr.match(/([A-Z]{3})\*?$/)
                  action.action_type = match[1]
                end
                amendment.actions << action 

              #  "ADD  P 23 Costa Rica"
              elsif segs[1] == 'P' && segs[0].match(/^(ADD|LIR|SUP)\*?$/)
                action = Q708ISPCAction.new
                action.entries = []
                action.position = segs[1..2].join(" ")
                country = segs[3..-1].join(' ')
                action.action_type = segs[0]
                amendment.actions << action

              # "Cambodia P 12 REP all information by:" — country,
              # position, action keyword (possibly with trailing text).
              elsif (pm = single_space_str.match(/\A(.+) P (\d+) (ADD|LIR|REP|SUP)\b/))
                action = Q708ISPCAction.new
                action.entries = []
                action.position = "P #{pm[2]}"
                country = pm[1].strip
                action.action_type = pm[3]
                amendment.actions << action

              # "ADD Falkland Islands (Malvinas) P 20" — action keyword
              # first, then country, then position.
              elsif (pm = single_space_str.match(/\A(ADD|LIR|REP|SUP)\*? (.+) P (\d+)\b/))
                action = Q708ISPCAction.new
                action.entries = []
                action.position = "P #{pm[3]}"
                country = pm[2].strip
                action.action_type = pm[1]
                amendment.actions << action

              # "Netherlands LIR" or "Costa Rica ADD" or "Belgium ADD"
              # (matched on the whitespace-normalized form — printed
              # rows carry trailing padding spaces)
              elsif match = single_space_str.match(/^(.+) (ADD|LIR|SUP)\*?$/)
                action = Q708ISPCAction.new 
                action.entries = []
                # action.position = match[1].strip # no position supplied
                country = segs[0..-2].join(' ')
                action.action_type = segs[-1]
                amendment.actions << action 

              # actual data row
              else
                matched = false

                entry = Q708ISPCEntry.new 
                entry.ipsc = Ituob::Helpers.strip_legacy(rf[0])
                entry.country = MultilingualString.new(en: country)
                entry.dec = Ituob::Helpers.strip_legacy(rf[1])
                entry.signal_point_name = Ituob::Helpers.strip_legacy(rf[2])
                entry.signal_point_operator = Ituob::Helpers.strip_legacy(rf[3])
                action.entries << entry
              end

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
