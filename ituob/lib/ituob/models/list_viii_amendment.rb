# frozen_string_literal: true

module Ituob
  module Models
    # List VIII (List of Coast Stations, R_SP_LN.VIII) amendment.
    #
    # Two printed formats share one document model:
    #
    # Compact monitoring block (e.g. OB 1044):
    #   "RUS      Russian Federation"        country line
    #   "P   330    ADD     by alphabetical order"   P-line
    #   table 4c  "Centralizing office | Postal address | ..." header
    #             + one office row        -> CentralizingOffice
    #   table 3c  "Name of the station | ..." header + station row
    #   table 5c  "Geographical coordinates | Types of measurements |
    #             ..." header + measurement rows
    #   "RUS - Russian Federation (cont.)"  continuation
    #
    # Full-part republication (e.g. OB 1002):
    #   "PART  I B" / "ALPHABETICAL INDEX OF STATIONS"  part headings
    #   "PART II" / "Section A / Sección A" + bilingual section titles
    #   P-lines like "P  43   COL 1-6   ADD" / "P 133   REP *"
    #   6c/7c Part I index tables (bilingual header + number row +
    #   station rows with Part II/III references)
    #   7c/8c Section A/B/C measurement tables (bilingual header +
    #   sub-header + number row + station measurement rows)
    #   3c bilingual footnote tables ("1)  7 active antenna elements")
    #
    # Header and column-number wording carries printed tokens, so it
    # is kept as amendment notes; bilingual footnotes are notes.
    class ListVIIIAmendment < Amendment

      attribute :actions, ListVIIIAction, collection: true
      attribute :_class, :string, default: -> { self.name.split('::').last }

      key_value do
        map '_class', to: :_class, render_default: true
        map 'position_on', to: :position_on
        map 'actions', to: :actions
        map 'notes', to: :notes
      end

      # Walk payload for one document parse: action lifecycle on the
      # shared WalkState; this adds the List VIII walk fields.
      class State < WalkState
        ACTION_CLASS = ListVIIIAction

        attr_accessor :country, :station, :section, :measurement_type,
                      :pending_office
        attr_reader :amendment, :notes

        def initialize(amendment)
          super(action_class: ACTION_CLASS)
          @amendment = amendment
          @notes = []
        end
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new
        amendment.position_on = position_on if position_on

        state = State.new(amendment)
        blocks = Ituob::Helpers.dump_doc(Prosereflect::Parser.parse_document(hash))
        blocks.each { |block| consume_block(block, state) }
        # An amendment can end on the office table alone (no station
        # row follows) — keep the office on a station of its own.
        flush_pending_office(state)
        state.close

        amendment.actions.concat(state.actions)
        amendment.notes.concat(state.notes)
        amendment
      end

      def self.consume_block(block, state)
        return if block.nil? || block.empty?

        if block.first.is_a?(String)
          consume_paragraph(block, state)
        else
          consume_table(block, state)
        end
      end

      def self.consume_paragraph(paragraph_texts, state)
        text = Ituob::Helpers.normalize_whitespace(paragraph_texts.join(' '))
        return if text.empty?

        # Country line: "RUS  Russian Federation" (3-letter code plus
        # name), possibly with "(cont.)"/"(continuation)". Runs of
        # spaces were collapsed by normalize_whitespace, so match single spaces.
        if (c_line = text.match(/\A([A-Z]{2,3})\s+(\p{Lu}\p{L}[\p{L}'’()\- ]*)(?:\s+\((?:cont\.|continuation)\))?\z/))
          state.country = "#{c_line[1]} #{c_line[2]}".strip
          state.station = nil
          return
        end

        # P-line: "P 43   COL 1-6   ADD   by alphabetical order" or
        # "P 133          REP *".
        if (p_line = text.match(/\AP\s+(\d+)\s*(.*)\z/))
          flush_pending_office(state)
          action = state.open_action
          action.position = "P #{p_line[1]}"
          action.description = text
          action.country = state.country
          rest = p_line[2]
          keyword = action_keyword_in(rest)
          action.action_type = keyword if keyword
          return
        end

        # Section headings ("Section A / Sección A") prime the
        # measurement context; the following bilingual line names the
        # measurement type. Both are kept printed.
        if (s_line = text.match(/\ASection ([A-Z])/))
          state.section = s_line[1]
          state.measurement_type = nil
          state.notes << text
          return
        end
        if state.section && state.measurement_type.to_s.empty? && text.match?(%r{/}) && !text.match?(/\AP\s/)
          state.measurement_type = text
        end

        # Index-only announcements: "Station:   Chengdu" plus a MARS
        # profile URL — a station with no printed table.
        if (st_line = text.match(/\AStation:\s+(.+)\z/))
          open_station([st_line[1], '', ''], state)
          return
        end
        state.notes << text
      end

      def self.consume_table(rows, state)
        rows.each do |row|
          texts = row.map { |cell| Ituob::Helpers.normalize_whitespace(cell.join(' ')) }
          next if texts.all?(&:empty?)

          if texts.length == 1
            consume_country_row(texts[0], state)
          elsif number_row?(texts)
            next
          elsif header_row?(texts)
            # Printed header wording (bilingual) carries tokens.
            state.notes << texts.map { |t| t unless t.empty? }.compact.join(' — ')
          elsif texts.length == 3 && footnote_row?(texts)
            state.notes << texts.join(' — ')
          elsif texts.length == 3
            # Station row (name | postal address | contact) — the only
            # other 3-column shape after headers, footnotes and
            # section lines are classified above.
            open_station(texts, state)
          elsif texts.length == 4
            attach_centralizing_office(texts, state)
          elsif texts.length == 5
            add_measurement(texts, state)
          elsif texts.length >= 6
            consume_wide_row(texts, state)
          else
            # Unrecognized shape (e.g. bilingual sub-headers) — keep
            # the printed wording rather than dropping it silently.
            state.notes << texts.map { |t| t unless t.empty? }.compact.join(' — ')
          end
        end
      end

      # 1-cell rows: country headers ("RUS - Russian Federation").
      def self.consume_country_row(text, state)
        if text.match?(/\A[A-Z]{2,3}\s*-\s/)
          state.country = text
          state.station = nil
        else
          state.notes << text
        end
      end

      # "1 | 2 | 3 | 4 | 5a | 5b | 6" column-number rows.
      def self.number_row?(texts)
        texts.compact.all? { |t| t.match?(/\A\d{1,2}[ab]?\z/) } && texts.length >= 2
      end

      # Bilingual header rows: "Name of the station | ...", "Nom de la
      # station | ...", "Geographical coordinat...", "Centralizing
      # office | ...", "Section Sección | Page ...", sub-headers.
      def self.header_row?(texts)
        joined = texts.join(' ')
        joined.match?(/Nom de la station|Name of the station|Geographical coor|Centralizing office|Section Sección|Coordonnées géogra|Types of measur|Gammes des fréqu|Heures de service/i)
      end

      # "1)  7 active antenna elements" bilingual footnote rows.
      def self.footnote_row?(texts)
        texts.first.to_s.match?(/\A\d+\)/)
      end

      def self.open_station(texts, state)
        station = ListVIIIStation.new(
          country: state.country,
          name: texts[0],
          postal_address: texts[1],
          contact: texts[2],
        )
        station.centralizing_office = state.pending_office if state.pending_office
        state.pending_office = nil
        state.station = station
        state.ensure_action.entries << station
        station
      end

      # The office table can be printed BEFORE its station table; hold
      # it as pending and attach to the next opened station.
      def self.attach_centralizing_office(texts, state)
        office = ListVIIICentralizingOffice.new(
          name: texts[0], postal_address: texts[1],
          contact: texts[2], remarks: texts[3],
        )
        if state.station
          state.station.centralizing_office = office
        else
          # Office-only amendments (no station row follows): flush any
          # earlier pending office onto a station of its own before
          # this one replaces it.
          flush_pending_office(state)
          state.station = nil
          state.pending_office = office
        end
      end

      # Materialize a pending office (from an office-only amendment)
      # as a station named after the office, on the current action.
      def self.flush_pending_office(state)
        return unless state.pending_office

        station = ListVIIIStation.new(
          country: state.country,
          name: state.pending_office.name,
          centralizing_office: state.pending_office,
        )
        state.pending_office = nil
        state.station = station
        state.ensure_action.entries << station
        station
      end

      # Compact 5c measurement row: coordinates | type | ranges |
      # hours | remarks.
      def self.add_measurement(texts, state)
        station = state.station || open_station(['', '', ''], state)
        station.measurements << ListVIIIMeasurement.new(
          section: state.section,
          measurement_type: state.measurement_type || texts[1],
          coordinates: texts[0],
          hours_of_service: texts[3],
          frequency_ranges: texts[2],
          remarks: texts[4],
        )
      end

      # Wide Part I index / Section measurement rows (6-8 columns).
      #   Part I: name | address | phone | fax | part II ref | part III ref
      #   Section: name | coords | hours | ranges | ...precision/values |
      #            remarks — extra columns kept verbatim in details.
      def self.consume_wide_row(texts, state)
        if texts[1].to_s.match?(/,\s*\d|Str\.|proezd|street|ave\.|ul\.|pr\./i) && texts[2].to_s.match?(/\+|\d{3}/)
          # Part I index row: station with contacts + references.
          station = ListVIIIStation.new(
            country: state.country,
            name: texts[0],
            postal_address: texts[1],
            contact: [texts[2], texts[3]].reject(&:empty?).join(' '),
            part_ii_reference: texts[4],
            part_iii_reference: texts[5],
          )
          state.station = station
          state.ensure_action.entries << station
        else
          # Section measurement row. Column 0 names the station —
          # consecutive rows for the same station repeat it (or use
          # the ditto mark "»"), a NEW name opens a new station.
          if !texts[0].to_s.empty? && texts[0] != '»' && state.station&.name != texts[0]
            open_station([texts[0], '', ''], state)
          end
          station = state.station || open_station(['', '', ''], state)
          station.measurements << ListVIIIMeasurement.new(
            section: state.section,
            measurement_type: state.measurement_type,
            coordinates: texts[1],
            hours_of_service: texts[2],
            frequency_ranges: texts[3],
            details: texts[4..].to_a.reject(&:empty?).join(' '),
          )
        end
      end

    end
  end
end
