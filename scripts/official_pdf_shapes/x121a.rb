# frozen_string_literal: true

require_relative 'base'
require_relative 'g4_text'

module OfficialPdfComparison
  module Shapes
    # X.121 data country codes: a three digit code and a country name, listed
    # zone by zone; a long name wraps under the name column. The amendment-record table (bare numbers) has no names and
    # the "Zone n, number of codes in reserve" lines are summaries, not rows.
    class X121A < Base
      include G4Prose

      PUBLICATIONS = %w[T-SP-X.121A-2011].freeze
      CODE = /\A\s*(\d{3})\s{2,}(\S.*)\z/

      def rows(text)
        out = []
        name_col = nil
        G4Text.lines_of(text).each do |line|
          if (m = CODE.match(line))
            out << Row.new(m[1], G4Text.squish(m[2]))
            name_col = m.begin(2)
          elsif name_col && line.match?(/\A {#{name_col - 1},}\S/) && !G4Text.furniture?(line)
            out.last.text = G4Text.squish("#{out.last.text} #{line}")
          else
            name_col = nil
          end
        end
        out
      end
    end
  end
end
