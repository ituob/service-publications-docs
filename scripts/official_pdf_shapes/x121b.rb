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
      CODE = '(?<code>\d{3} \d{1,4}(?:-\d{1,4})?)'
      # Code first on the line (one space before the name is enough), or after
      # the country name with two or more spaces round the code. Lower-case words
      # after a lone code are running text (a form note), not a network name.
      DNIC = /\A\s*#{CODE}\s+(?<net>(?![[:lower:]]\S*\s)[^\d\s].*)\z|\A\S.*?\s+#{CODE}\s{2,}(?<net>[^\d\s].*)\z/

      def rows(text)
        out = []
        net_col = nil # column of the network name on the last code line; nil when no row is open
        G4Text.lines_of(text).each do |line|
          if (m = DNIC.match(line)) && !G4Text.furniture?(line)
            out << Row.new(m[:code], G4Text.squish(m[:net]))
            net_col = m.begin(:net)
          elsif net_col && (cont = wrap_text(line, net_col))
            out.last.text = G4Text.squish("#{out.last.text} #{cont}")
          else
            net_col = nil
          end
        end
        out
      end

      private

      # A network name wraps onto the next line, under the network column. The
      # generated PDF puts the next country name (English) on that line, so the
      # text in the network column can follow country text; the official PDF
      # indents the wrap line instead.
      def wrap_text(line, net_col)
        return if G4Text.furniture?(line)
        return line.strip if line.match?(/\A {20,}\S/)
        return if line.size <= net_col || line[net_col - 1] != ' '

        line[net_col..].then { |t| t.strip.empty? || t.match?(/\A\s/) ? nil : t }
      end
    end
  end
end
