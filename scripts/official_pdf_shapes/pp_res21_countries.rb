# frozen_string_literal: true

require_relative 'base'
require_relative 'g3_support'

module OfficialPdfComparison
  module Shapes
    # T-SP-PP.RES.21-2011: a numbered list of countries, printed in two
    # columns, so one text line carries two rows. A row is a number and its
    # name; rows are returned in number order (the reading order of the list).
    class PpRes21Countries < Base
      PUBLICATIONS = %w[T-SP-PP.RES.21-2011].freeze
      START = %r{\A\s*(?:Countries/|Pays/|Países/)}
      ENTRY = /\A(\d{1,3})\s+(\S.*)\z/

      def rows(text)
        lines = G3Support.lines(text)
        from = lines.index { |l| l.match?(START) }
        return [] unless from

        lines.drop(from + 1).flat_map do |line|
          next [] if G3Support.furniture?(line)

          G3Support.cells_at(line).filter_map { |cell, _| cell.match(ENTRY) { |m| Row.new(m[1], G3Support.squish(m[2])) } }
        end.sort_by { |r| r.key.to_i }
      end
    end
  end
end
