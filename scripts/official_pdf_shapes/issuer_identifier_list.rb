# frozen_string_literal: true

require_relative 'base' if File.exist?(File.join(__dir__, 'base.rb'))
require_relative 'g1_support'

module OfficialPdfComparison
  module Shapes
    # E.118 list of Issuer Identifier Numbers. One row per IIN: country,
    # company name/address, "89 <country> <seq>" and the contact block.
    # The Arabic PDFs are right to left: pdftotext prints the columns mirrored
    # and the generated PDF's IIN reversed ("01 93 89"), so there a row's text
    # is its sorted words and the IIN is read in either direction.
    class IssuerIdentifierList < Base
      PUBLICATIONS = %w[T-SP-E.118-2018].freeze
      IIN = /(?<!\d)(?<!\d )(?:89(?: \d{1,3}){2}|\d{1,3} \d{1,3} 89)(?!\d)/
      ARABIC = /[؀-ۿ]/
      # a page number, or the heading of the section that follows the table (numbered,
      # or alone on the first line of a page: "AMENDMENTS")
      END_OF_TABLE = /\A\s*(?:\d+|\d+\.\s+[[:upper:]]{4,}.*)\s*\z/
      SECTION_HEADING = /\A\s*[[:upper:]]{5,}\s*\z/

      def rows(text)
        rtl = text.scan(ARABIC).size > 200
        groups = []
        lines = G1Support.body_lines(text)
        page_first = lines.group_by(&:page).transform_values { |ls| ls.find { |l| !l.text.strip.empty? } }.values
        lines.each do |line|
          if (m = line.text.match(IIN))
            # a narrow company column leaves one space before the IIN: cut it out
            groups << { key: key(m[0]), lines: [G1Support::Line.new(line.text.sub(IIN) { "  #{m[0]}  " }, line.page)] }
          elsif groups.any? && !groups.last[:done]
            line.text =~ END_OF_TABLE || (line.text =~ SECTION_HEADING && page_first.include?(line)) ? groups.last[:done] = true : groups.last[:lines] << line unless line.text.strip.empty?
          end
        end
        heads = G1Support.page_heads(groups.map { |g| g[:lines].first })
        G1Support.unique_keys(groups.map { |g| Row.new(g[:key], row_text(g[:lines], heads, rtl)) })
      end

      def prose_stop(lines, start) = G1Support.prose_stop(lines, start) { |line, _| line.match?(IIN) }

      private

      # sorted words with the Arabic letters cut out (they glue onto the
      # neighbouring Latin text in the official PDF)
      def mirrored_text(lines)
        lines.map(&:text).join(' ').gsub(IIN, '').gsub(/[\u0600-\u06FF\u0750-\u077F\uFB50-\uFEFF]+/, ' ').downcase.scan(/[[:alnum:]]+/).sort.join(' ')
      end

      def key(iin)
        parts = iin.split
        parts.last == '89' ? parts.reverse.join(' ') : iin
      end

      def row_text(lines, heads, rtl)
        return mirrored_text(lines) if rtl

        G1Support.column_text(lines, heads, align: :start)
      end
    end
  end
end
