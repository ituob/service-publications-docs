# frozen_string_literal: true

require_relative 'base'
require_relative 'g3_support'

module OfficialPdfComparison
  module Shapes
    # T-SP-PP.RES.21-2011: a numbered list of countries, printed in two
    # columns, so one text line carries two rows. A row is a number and its
    # name. The official F and S lists number the countries in their own
    # alphabetical order while the generated ones keep the English numbering,
    # so a row is keyed by the name, its text is the number, and rows come
    # back sorted by name: a renumbered country is one delta, not a shifted list.
    class PpRes21Countries < Base
      PUBLICATIONS = %w[T-SP-PP.RES.21-2011].freeze
      START = %r{\A\s*(?:Countries/|Pays/|Países/)}
      # Two columns: a run of three or more spaces before the next number.
      COLUMN_GAP = /\s{3,}(?=\d{1,3}\s)/
      ENTRY = /\A(\d{1,3})\s+(\S.*)\z/

      # The preface (Note from TSB, address, disclaimer) ends where the country
      # list starts; the generated PDF repeats the note heading before the list.
      def prose_stop(lines, start)
        lines.index.with_index { |l, i| i > start && l.match?(START) } || lines.size
      end

      def rows(text)
        lines = G3Support.lines(text)
        from = lines.index { |l| l.match?(START) }
        return [] unless from

        lines.drop(from + 1).flat_map do |line|
          next [] if G3Support.furniture?(line)

          line.strip.split(COLUMN_GAP).filter_map { |cell| cell.match(ENTRY) { |m| Row.new(G3Support.squish(m[2]), m[1]) } }
        end.sort_by { |r| [OfficialPdfComparison.normalise(r.key), r.text.to_i] }
      end
    end
  end
end
