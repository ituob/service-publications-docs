# frozen_string_literal: true

module Ituob
  module Models
    # X.121 DNIC (List of Data Network Identification Codes) amendment.
    #
    # Source document model (one ProseMirror document per amendment):
    #
    #   "(Annex to ITU OB No. 977 – 1.IV.2011) (Amendment No. 8)" — annex
    #       reference paragraph → amendment notes.
    #   P-line, one of:
    #     "P    206 6    SUP"          P + DNIC + action
    #     "P  13  United States  ADD"  P + page + country + action
    #     "P 14  Japan  REP all information by:"  P + page + country +
    #                                      action + change description
    #     "P21   240 2   SUP"          P + page + DNIC + action
    #   country-line: "SENEGAL LIR", "Spain    SUP"
    #   DNIC-list-line: "206 1, 206 2, … 206 9   SUP"
    #   "See also pages 4-5 of this ITU Operational Bulletin No. 1129."
    #       and everything after a "____" separator → amendment notes.
    #   table — 3 columns; the printed header row wording varies by
    #       action ("Name of network to which a DNIC is allocated" vs
    #       "… is withdrawn") and is kept as the action caption.
    #       Country cells print fr/en/es in one cell ("BELGIQUE BELGIUM
    #       BÉLGICA"), as paragraphs, or across consecutive rows
    #       ("ÉTATS-UNIS" / "UNITED STATES" / "ESTADOS UNIDOS").
    class X121DNICAmendment < Amendment

      attribute :actions, X121DNICAction, collection: true
      attribute :_class, :string, default: -> { self.name.split('::').last }

      key_value do
        map '_class', to: :_class, render_default: true
        map 'position_on', to: :position_on
        map 'actions', to: :actions
      end

      # Walk payload for one document parse: action lifecycle on the
      # shared WalkState; this adds the X.121 walk fields.
      class State < WalkState
        ACTION_CLASS = X121DNICAction

        attr_accessor :country, :in_notes
        attr_reader :notes

        def initialize
          super(action_class: ACTION_CLASS)
          @notes = []
        end
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new
        amendment.position_on = position_on if position_on

        blocks = Ituob::Helpers.dump_doc(Prosereflect::Parser.parse_document(hash))
        state = State.new
        blocks.each { |block| consume_block(block, state) }
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
        text = paragraph_texts
               .map { |p| Ituob::Helpers.replace_legacy_space(p.to_s) }
               .join(' ').gsub(/\s+/, ' ').strip
        return if text.empty?

        if text.match?(/\A_{3,}/)
          state.in_notes = true
          return
        end
        if state.in_notes || note_paragraph?(text)
          state.notes << text
          return
        end

        if (p_line = text.match(/\AP\s*(\d+)?\s+(.*)\z/))
          action = state.open_action
          base_position = p_line[1] ? "P #{p_line[1]}" : 'P'
          action.position = base_position
          apply_change_text(action, p_line[2])
          # "P  206 6  SUP": the DNIC digits straddle the P-number and
          # the remainder — rejoin them when no DNIC was found already.
          if action.position == base_position && p_line[2].match?(/\A\d{1,3}\b/)
            dnic_rest = p_line[2].split(/\s+/).first
            action.position = "#{base_position} #{dnic_rest}"
          end
          action.description = text
        else
          action = state.ensure_action
          apply_change_text(action, text)
          action.description = text
        end
      end

      # Derive country / DNIC position / action keyword from the text
      # following the P marker (or from a bare country / DNIC-list line).
      def self.apply_change_text(action, text)
        action_type = action_keyword_in(text)
        if action_type
          action.action_type = action_type
          head = text.sub(/\b#{action_type}\b.*\z/, '').strip
        else
          head = text.strip
        end

        dnic = head.match(/\A(\d{3}(?:[ ,]+\d{1,3})+(?:[ ,]+\d{3}[ ,]+\d{1,3})*)/)
        if dnic
          # "206 6" or "206 1, 206 2, … 206 9" — DNIC list is the position.
          action.position = "#{action.position} #{dnic[1]}".strip if action.position
        elsif head.match?(/\A[\p{L} .’'-]+\z/)
          state_country = Ituob::Helpers.strip_legacy(head)
          action.country = state_country unless state_country.to_s.empty?
        end
      end

      # Printed paragraphs that belong to the notes, not to a change line.
      def self.note_paragraph?(text)
        text.match?(/\A\*/) ||
          text.match?(/\A\d+\)/) ||
          text.match?(/\A\(Annex/i) ||
          text.match?(/\ASee (also )?(page|Data|pages)/i) ||
          text.match?(/\ACorrigendum/i)
      end

      def self.consume_table(rows, state)
        rows.each do |cells|
          texts = cells.map { |cell| cell.map { |p| Ituob::Helpers.normalize_whitespace(p) }.reject(&:empty?) }
          next if texts.all?(&:empty?)

          if texts.length != 3
            next
          elsif header_row?(texts)
            # Printed header — its wording ("… is allocated"/"… is
            # withdrawn") is semantic; keep it as the table caption.
            state.ensure_action.caption = texts.map { |c| c.join(' ') }.join(' — ')
          elsif texts[0] == ['1'] && texts[1] == ['2']
            # column-number row
          elsif country_only_row?(texts)
            merge_country_variant(state, texts[0])
          else
            state.ensure_action.entries << build_entry(texts, state)
          end
        end
      end

      def self.header_row?(texts)
        texts[0].first.to_s.match?(/\ACountry\/?\b/i)
      end

      def self.country_only_row?(texts)
        texts[1].empty? && texts[2].empty? && !texts[0].empty?
      end

      def self.build_entry(texts, state)
        if texts[0].length > 3
          # "HONGRIE | HUNGARY | HUNGRÍA | 1) use internally, …" — the
          # paragraphs beyond the three languages are cell footnotes.
          extra = texts[0].drop(3).join(' ')
        else
          extra = nil
        end

        country = texts[0].first(3).join(' ').strip
        state.country = trilingual_country(texts[0].first(3)) unless country.empty?

        entry = X121DNICEntry.new(
          country_or_area: state.country,
          dnic_number: texts[1].join(' ').strip,
          network_name: texts[2].join(' ').strip,
        )
        entry.note = extra if extra
        entry
      end

      # A country-only row prints one language of the current country;
      # fill the first empty fr/en/es slot (or open a new country).
      def self.merge_country_variant(state, paragraphs)
        value = paragraphs.first(3).join(' ').strip
        return if value.empty?

        if state.country.nil?
          state.country = trilingual_country(paragraphs.first(3))
          return
        end

        %i[en es fr].each do |lang|
          next if state.country.public_send(lang)

          state.country.public_send("#{lang}=", value) unless language_values(state.country).include?(value)
          break
        end
      end

      def self.language_values(country)
        %i[fr en es].map { |lang| country.public_send(lang) }.compact
      end

      # Country cells print fr/en/es as paragraphs, one line, or one
      # word per row (FR prints first). Three paragraphs or a
      # three-word trilingual line map positionally; any other single
      # value defaults to fr.
      def self.trilingual_country(paragraphs)
        parts = paragraphs.map { |p| Ituob::Helpers.normalize_whitespace(p) }.reject(&:empty?)
        if parts.length == 3
          MultilingualString.new(fr: parts[0], en: parts[1], es: parts[2])
        elsif parts.length == 1 && parts[0].match?(/\A[\p{Lu}\p{M}'’\-\.]{2,}( [\p{Lu}\p{M}'’\-\.]{2,}){2}\z/)
          words = parts[0].split(/\s+/)
          MultilingualString.new(fr: words[0], en: words[1], es: words[2])
        else
          MultilingualString.new(fr: parts.join(' '))
        end
      end

    end
  end
end
