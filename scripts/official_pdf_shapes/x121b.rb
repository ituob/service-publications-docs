# frozen_string_literal: true

require_relative 'base'
require_relative 'g4_text'

module OfficialPdfComparison
  module Shapes
    # X.121 DNIC list: country name (three languages), a 3+1 digit DNIC and the
    # network name, which may wrap. Row key is the DNIC, text the network name.
    # The country cell is not part of the row: the official PDF prints its three
    # language names on the first three code lines of a block, the generated PDF
    # splits them over code and bare lines, so no per-row reading is stable.
    class X121B < Base
      include G4Prose

      PUBLICATIONS = %w[T-SP-X.121B-2011].freeze
      DNIC = /\A.*?\s*(?<code>\d{3} \d)\s{2,}(?<net>\S.*)\z/
      WRAP_COL = 20

      def rows(text)
        out = []
        open_row = false # the previous line was a code line or its wrap
        G4Text.lines_of(text).each do |line|
          if (m = DNIC.match(line)) && !G4Text.furniture?(line)
            out << Row.new(m[:code], G4Text.squish(m[:net]))
            open_row = true
          elsif open_row && line.match?(/\A {#{WRAP_COL},}\S/) && !G4Text.furniture?(line)
            out.last.text = G4Text.squish("#{out.last.text} #{line}")
          else
            open_row = false
          end
        end
        out
      end
    end
  end
end
