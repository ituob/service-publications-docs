# frozen_string_literal: true

module Ituob
  module Models
    # NNP (National Numbering Plans) amendment.
    #
    # Source document model (one ProseMirror document per amendment,
    # uniform across all 348 issues):
    #
    #   intro paragraphs — "Administrations are requested to notify
    #       ITU...", "From 1.V.2017 the following countries... have
    #       updated their national numbering plans..." → amendment
    #       notes (the intro carries the effective date).
    #   one 2-column table — "Country/Geographical area | Country
    #       Code (CC)"; data rows like "Kosovo * | +383" become
    #       NumberingPlanEntry records (country + code; the other
    #       printed plan columns do not appear in this listing).
    #       Values are kept verbatim, footnote markers included.
    #
    # The whole issue is one listing action — NNP prints no P lines.
    class NNPAmendment < Amendment
      attribute :actions, NNPAction, collection: true
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

        action = NNPAction.new
        action.entries = []
        amendment.actions << action

        blocks = Ituob::Helpers.dump_doc(Prosereflect::Parser.parse_document(hash))
        blocks.each { |block| consume_block(block, action, amendment) }
        amendment
      end

      def self.consume_block(block, action, amendment)
        return if block.nil? || block.empty?

        if block.first.is_a?(String)
          text = Ituob::Helpers.normalize_whitespace(block.join(' '))
          amendment.notes << text unless text.empty?
        else
          block.each { |row| consume_row(row, action) }
        end
      end

      def self.consume_row(row, action)
        texts = row.map { |cell| Ituob::Helpers.normalize_whitespace(cell.join(' ')) }
        return if texts.all?(&:empty?)
        # Printed header rows ("Country/Geographical area | Country
        # Code (CC)", and the stray single-cell "Country" fragment).
        return if texts.join(' ').match?(/\ACountry\/?\b/i)

        entry = NumberingPlanEntry.new(
          country_or_area: MultilingualString.new(en: texts[0]),
          country_code: texts[1].to_s,
        )
        action.entries << entry unless texts[0].to_s.empty?
      end

    end
  end
end
