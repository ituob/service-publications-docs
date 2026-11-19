# frozen_string_literal: true

require 'unicode_normalize/normalize'
require_relative 'base'

module OfficialPdfComparison
  module Shapes
    # Helpers shared by the code-keyed table shapes (E.212A, E.212B, E.218,
    # Q.708A, Q.708B). `pdftotext -layout` lines go in; per-row text comes out.
    module ColumnRows
      Row = Shapes::Row
      BIDI = /[‎‏‪-‮⁦-⁩]/
      # "– 4 –", or "– – 4" where bidi reordering moved the number.
      PAGE_NUMBER = /(?:\A|\s)(?:[–—-]\s*\d+\s*[–—-]|[–—-]\s*[–—-]\s*\d+|\d+\s*[–—-]\s*[–—-])(?:\s|\z)/

      # Where the preface sits in the code-table publications. Their table header
      # is not F.32's, so Base#prose_stop would run to the end of the PDF and
      # every table row would also be compared as prose. The preface starts at
      # the "Note from TSB" heading (E.218 and Q.708A Chinese print "说明" without "的";
      # Q.708A English "Note by TSB") and ends at the first page break or, in a
      # PDF whose page number is mangled, at the first table row (`row_line?`).
      module Prose
        PREFACE = /\A(?:Note (?:from|by) TSB|Note du TSB|Nota de la TSB|电信标准化局的?说明|Примечание БСЭ|مالحظة|ملاحظة)/

        def prose_start(lines, _lang)
          lines.index { |l| ColumnRows.clean_lines(l).first.to_s.strip.match?(PREFACE) } || 0
        end

        def prose_stop(lines, start)
          lines.index.with_index do |l, i|
            next false unless i > start

            c = ColumnRows.clean_lines(l).first.to_s
            c.match?(PAGE_NUMBER) || row_line?(c)
          end || lines.size
        end
      end

      module_function

      # Lines with bidi controls dropped and Arabic presentation forms folded
      # (NFKC), so both PDFs read the same letters.
      def clean_lines(text)
        text.unicode_normalize(:nfkc).gsub(BIDI, '').lines.map(&:rstrip)
      end

      # One space between words; none next to a Han character (justified CJK
      # lines gain spaces around brackets and between characters).
      def squeeze(str) = str.strip.gsub(/\s+/, ' ').gsub(/(?<=\p{Han}) | (?=\p{Han})/, '')

      def indent(line) = line[/\A */].size

      # Rows whose key repeats get "#2", "#3" ... so keys identify one row each.
      def unique_keys(rows)
        seen = Hash.new(0)
        rows.map do |row|
          seen[row.key] += 1
          n = seen[row.key]
          n == 1 ? row : Row.new("#{row.key}##{n}", row.text)
        end
      end

      # Headings after the last row of a table (forms, notes) head nothing.
      def drop_trailing_headings(rows)
        rows.pop while rows.last&.key&.start_with?('country:')
        rows
      end

      # Lines of the table body only: the prose before the first row, and the
      # repeated header block after every page-number line, are dropped.
      # `row_re` recognises a row line; `header_free` lines never count.
      def body(lines, &row)
        out = []
        skipping = true
        lines.each do |line|
          if line.match?(PAGE_NUMBER)
            skipping = true
            next
          end
          skipping = false if skipping && row.call(line)
          out << line unless skipping
        end
        out
      end
    end
  end
end
