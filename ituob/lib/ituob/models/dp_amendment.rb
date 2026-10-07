# frozen_string_literal: true

module Ituob
  module Models
    # DP (national numbering plan) amendment.
    #
    # Source document model (one ProseMirror document per amendment,
    # uniform across the corpus):
    #
    #   header table (7 columns, single row): "Country/geographical
    #       area | Country code | International prefix | National
    #       prefix | National (significant) number | UTC/DST | Note"
    #       — printed column titles, skipped.
    #   action paragraph: "P  4   Djibouti LIR" — position "P 4",
    #       printed country, action keyword.
    #   data table (7 columns, single row): the plan itself — one
    #       DPEntry (a NumberingPlanEntry) with all seven printed
    #       fields.
    #
    # Replaced the previous Prosereflect-API walk that extracted
    # nothing (every DP issue rendered via the text fallback); see
    # TODO.complete/51.
    class DPAmendment < Amendment

      attribute :actions, DPAction, collection: true
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

        action = DPAction.new
        action.entries = []
        amendment.actions << action

        blocks = Ituob::Helpers.dump_doc(Prosereflect::Parser.parse_document(hash))
        blocks.each { |block| consume_block(block, action, amendment) }
        amendment
      end

      def self.consume_block(block, action, amendment)
        return if block.nil? || block.empty?

        if block.first.is_a?(String)
          consume_paragraph(block, action, amendment)
        else
          block.each { |row| consume_row(row, action) }
        end
      end

      def self.consume_paragraph(paragraph_texts, action, amendment)
        text = Ituob::Helpers.normalize_whitespace(paragraph_texts.join(' '))
        return if text.empty?

        if (p_line = text.match(/\AP\s*(\d+)\s+(.*)\z/))
          action.position = "P #{p_line[1]}"
          action.description = text
          rest = p_line[2]
          keyword = action_keyword_in(rest)
          action.action_type = keyword if keyword
          country = keyword ? rest.sub(/\b#{keyword}\b.*\z/, '').strip : rest.strip
          action.country = country unless country.empty?
        else
          amendment.notes << text
        end
      end

      def self.consume_row(row, action)
        texts = row.map { |cell| Ituob::Helpers.normalize_whitespace(cell.join(' ')) }
        return if texts.all?(&:empty?)
        # Printed header row ("Country/geographical area | ...").
        return if texts.join(' ').match?(/\ACountry\/?\b/i)
        return unless texts.length >= 7

        entry = DPEntry.new(
          country_or_area: MultilingualString.new(en: texts[0]),
          country_code: texts[1],
          international_prefix: texts[2],
          national_prefix: texts[3],
          national_sig_number: texts[4],
          utc_dst: texts[5],
          note: MultilingualString.new(en: texts[6]),
        )
        action.entries << entry
      end

    end
  end
end
