# frozen_string_literal: true

require_relative 'base'
require_relative 'g3_support'

module OfficialPdfComparison
  module Shapes
    # T-SP-F.1-1998: five-letter code groups. The rows are list entries, not
    # table cells: a code and its meaning, the meaning wrapping onto indented
    # lines. The code groups appear twice, in Part I (decoding) and in Part II
    # (coding, under field headings), so the key carries the part.
    class F1CodeGroups < Base
      PUBLICATIONS = %w[T-SP-F.1-1998].freeze
      CODE = /\A\s*([A-Z](?: ?[A-Z]){4})\s{2,}(\S.*)\z/
      PART_II = /\bPart(?:ie|e)?\s+II\s+-/
      MEANING_SLACK = 2
      # The preface runs from the TSB note ("Note from the TSB": Base's marker
      # lacks the "the") to the Part I heading, where the code lists begin.
      NOTE = /\A(?:Note from the TSB|Note du TSB|Nota de la TSB)\z/
      PART_I = /\bPart(?:ie|e)?\s+I\s+[-–]/

      def prose_start(lines, _lang) = lines.index { |l| l.strip.match?(NOTE) } || 0

      def prose_stop(lines, start)
        lines.index.with_index { |l, i| i > start && l.match?(PART_I) } || lines.size
      end

      def rows(text)
        part = 'I'
        out = []
        meaning_col = nil
        G3Support.lines(text).each do |line|
          part = 'II' if line.match?(PART_II)
          next if line.strip.empty? || G3Support.furniture?(line)

          if (m = line.match(CODE))
            out << Row.new("#{part}:#{m[1].delete(' ')}", m[2])
            meaning_col = line.index(m[2])
          elsif meaning_col && out.any? && (line[/\A */].size - meaning_col).abs <= MEANING_SLACK && line !~ /\A\s*[A-Z ]+\z/
            last = out.pop
            out << Row.new(last.key, "#{last.text} #{line.strip}")
          else
            meaning_col = nil
          end
        end
        out.map { |r| Row.new(r.key, G3Support.squish(r.text)) }
      end
    end
  end
end
