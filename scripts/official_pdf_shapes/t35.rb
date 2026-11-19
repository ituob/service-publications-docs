# frozen_string_literal: true

require_relative 'base'
require_relative 'g4_text'

module OfficialPdfComparison
  module Shapes
    # T.35 country codes: eight bit columns (b8..b1) then the country name.
    # One row per code; a name that wraps continues on indented lines below.
    class T35 < Base
      include G4Prose

      PUBLICATIONS = %w[T-SP-T.35-2012].freeze
      BITS = /\A\s*((?:[01]\s+){7}[01])\s{2,}(\S.*)\z/

      def rows(text)
        out = []
        open_row = false
        G4Text.lines_of(text).each do |line|
          if (m = BITS.match(line))
            out << Row.new(m[1].delete(' '), G4Text.squish(m[2]))
            open_row = true
          elsif open_row && wrap?(line)
            out.last.text = G4Text.squish("#{out.last.text} #{line}")
          else
            open_row = false
          end
        end
        out
      end

      private

      # A name continues on the very next line, indented under the name column.
      # A blank line, page furniture or the column header ends it.
      def wrap?(line)
        line.match?(/\A {40,}\S/) && !G4Text.furniture?(line)
      end
    end
  end
end
