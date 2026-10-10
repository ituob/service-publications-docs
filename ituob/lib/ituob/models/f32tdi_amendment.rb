# frozen_string_literal: true

module Ituob
  module Models
    # F.32 TDI (List of Telegram Destination Indicators) amendment.
    #
    # Source document model (one ProseMirror document per amendment):
    #
    #   "P  N  COUNTRY  ACTION"  paragraph — opens an action: position
    #                             ("P 27"), printed description, coarse
    #                             action keyword.
    #   "COL n ACTION ..."       paragraph — refines the position
    #                             ("P 27 COL 2"), sets the per-column
    #                             action and carries the change text
    #                             ("COL 2 REP Batelco ... by Unitel").
    #   table                    — 5-column data rows become entries;
    #                             1-cell rows are footnotes; 7-column
    #                             rows are embedded numbering-plan
    #                             notes ("Country code / International
    #                             prefix / ...").
    #   "*...", "N) ...", "Corrigendum*", and everything after a
    #   "____" separator are notes.
    #
    # Trilingual country cells print the fr/en/es name either as three
    # paragraphs ("LITUANIE | LITHUANIA | LITUANIA"), one paragraph
    # ("ALLEMAGNE GERMANY ALEMANIA"), or three consecutive rows
    # ("EGYPTE" / "EGYPT" / "EGIPTO"). Empty leading cells continue the
    # previous row's country/network, matching how the register prints.
    class F32TDIAmendment < Amendment

      attribute :actions, F32TDIAction, collection: true
      attribute :_class, :string, default: -> { self.name.split('::').last }

      key_value do
        map '_class', to: :_class, render_default: true
        map 'position_on', to: :position_on
        map 'actions', to: :actions
        map 'notes', to: :notes
      end

      # Walk payload for one document parse: the action lifecycle
      # lives on the shared WalkState; this adds the F.32 walk fields.
      class State < WalkState
        ACTION_CLASS = F32TDIAction

        attr_accessor :country, :network_roa, :network_code, :in_notes
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

        if (p_line = text.match(/\AP\s*(\d+(?:-\d+)?)?\s+(.*)\z/))
          action = state.open_action
          action.position = p_line[1] ? "P #{p_line[1]}" : 'P'
          action.description = text
          action.action_type = action_keyword_in(p_line[2]) || action.action_type
        elsif (col_line = text.match(/\ACOL\s*(\d+)\s*(.*)\z/))
          action = state.ensure_action
          action.position = "#{action.position} COL #{col_line[1]}".strip
          action.description = "#{action.description} #{text}".strip
          action.action_type = action_keyword_in(col_line[2]) || action.action_type
        else
          # Continuation of the change description ("by Unitel", "… Manama").
          state.ensure_action.description = "#{state.action.description} #{text}".strip
        end
      end

      # Footnote-like printed paragraphs that never belong to a change line.
      def self.note_paragraph?(text)
        text.match?(/\A\*/) ||
          text.match?(/\A\d+\)/) ||
          text.match?(/\ACorrigendum/i)
      end

      def self.consume_table(rows, state)
        rows.each do |cells|
          texts = cells.map { |cell| cell.map { |p| Ituob::Helpers.normalize_whitespace(p) }.reject(&:empty?) }
          next if texts.all?(&:empty?)

          if texts.length == 1
            state.notes << texts[0].join(' ')
          elsif numbering_header?(texts)
            # Printed header of the embedded numbering-plan table —
            # kept as a note so the printed wording renders.
            state.notes << texts.map { |cell| cell.join(' ') }.reject(&:empty?).join(' — ')
          elsif country_header?(texts) || column_header?(texts)
            # printed header rows — no data
          elsif texts.length == 7
            # Embedded numbering-plan table ("Country code / International
            # prefix / ...") carried inside the amendment for context.
            state.notes << texts.map { |cell| cell.join(' ') }.reject(&:empty?).join(' — ')
          elsif country_only_row?(texts)
            # Row printing only the country column: a fr/en/es variant of
            # the current country ("EGYPTE" / "EGYPT" / "EGIPTO" across
            # rows) — fill the next empty language slot.
            merge_country_variant(state, texts[0])
          elsif texts.length >= 5
            state.ensure_action.entries << build_entry(texts, state)
          elsif texts.length == 4
            merge_country_variant(state, texts[0])
          end
        end
      end

      def self.country_header?(texts)
        texts[0].first.to_s.match?(/\ACountry\/?\b/i)
      end

      def self.numbering_header?(texts)
        texts.length == 7 && texts[1].first.to_s.match?(/\ACountry code\z/i)
      end

      # Column-number header row ("1 | 2 | 3 | 4 | 5").
      def self.column_header?(texts)
        texts.length == 5 && texts[0] == ['1']
      end

      # Data row whose only populated cell is the country column.
      def self.country_only_row?(texts)
        texts.drop(1).all?(&:empty?) && !texts[0].empty?
      end

      # A country-only row prints one language of the current country.
      # Fill the first empty fr/en/es slot (or open a new country).
      def self.merge_country_variant(state, paragraphs)
        value = paragraphs.join(' ').strip
        return if value.empty?

        if state.country.nil?
          state.country = trilingual_country(paragraphs)
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

      def self.build_entry(texts, state)
        country = texts[0].join(' ').strip
        state.country = trilingual_country(texts[0]) unless country.empty?

        roa = texts[1].join(' ').strip
        state.network_roa = roa unless roa.empty?

        code = texts[2].join(' ').strip
        state.network_code = code unless code.empty?

        F32TDIEntry.new(
          country_or_area: state.country,
          network_roa: state.network_roa,
          network_code: state.network_code,
          telegraph_office_name: MultilingualString.new(en: texts[3].join(' ').strip),
          office_code: texts[4].to_a.join(' ').strip,
        )
      end

      # Country cells print fr/en/es as three paragraphs, one
      # space-separated line, or (across rows) one language per row
      # (the register prints FR first). Three paragraphs or a
      # three-word trilingual line map positionally; any other single
      # value defaults to the fr slot, and later variant rows fill
      # the remaining languages.
      def self.trilingual_country(paragraphs)
        parts = paragraphs.map { |p| Ituob::Helpers.normalize_whitespace(p) }.reject(&:empty?)
        if parts.length == 3
          MultilingualString.new(fr: parts[0], en: parts[1], es: parts[2])
        elsif parts.length == 1 && trilingual_line?(parts[0])
          words = parts[0].split(/\s+/)
          MultilingualString.new(fr: words[0], en: words[1], es: words[2])
        else
          MultilingualString.new(fr: parts.join(' '))
        end
      end

      def self.trilingual_line?(text)
        words = text.split(/\s+/)
        words.length == 3 &&
          words.all? { |w| w.length >= 3 } &&
          words.all? { |w| w.match?(/\A[\p{Lu}\p{M}'’\-\.]+\z/) || words.uniq.one? }
      end
    end
  end
end
