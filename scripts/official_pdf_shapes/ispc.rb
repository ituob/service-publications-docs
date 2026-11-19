# frozen_string_literal: true

require_relative 'column_rows'

module OfficialPdfComparison
  module Shapes
    # Q.708B: "Country | ISPC | DEC | Unique name of the signalling point |
    # Name of the signalling point operator". A country heading is a line
    # without a code, set in the first columns ("country:<name>"); a row is
    # keyed by its ISPC ("4-024-0"; a repeated ISPC gets "#2") and its text is
    # the sorted alphanumeric words of DEC, name and operator
    # (punctuation and hyphen breaks are not words). The two PDFs wrap those
    # cells differently, and a cell that fills its column leaves no gap to
    # split it by, so the order of words inside one row is not a measurement
    # and is dropped; every word of the row is still compared.
    class Ispc < Base
      include ColumnRows::Prose

      PUBLICATIONS = %w[T-SP-Q.708B-2016].freeze

      ROW = /\A\s*(?<ispc>\d-\d{3}-\d)\s+(?<rest>\d+(?:\s+\S.*)?)\z/
      REPEATED_HEADER = 5
      HEADING_INDENT = 8

      Line = Struct.new(:kind, :text, :indent, :ispc)

      def rows(text)
        @rows = []
        @row_words = nil
        @open_country = false
        from_table(classify(ColumnRows.clean_lines(text))).each { |l| read(l) }
        ColumnRows.unique_keys(ColumnRows.drop_trailing_headings(@rows))
      end

      def row_line?(line) = ROW.match?(line)

      private

      # Headings sit in the first columns; a wrapped cell never does.
      def heading?(line) = line.kind == :piece && line.indent <= HEADING_INDENT

      # Page furniture and the table header repeated on every page become
      # breaks (a heading line that recurs REPEATED_HEADER times is a header).
      def classify(raw_lines)
        lines = raw_lines.map { |raw| line(raw) }
        headers = lines.select { |l| heading?(l) }.map(&:text).tally
        lines.map { |l| heading?(l) && headers[l.text] >= REPEATED_HEADER ? Line.new(:break) : l }
      end

      def line(raw)
        return Line.new(:break) if raw.strip.empty? || raw.match?(ColumnRows::PAGE_NUMBER)

        m = ROW.match(raw)
        return Line.new(:row, ColumnRows.squeeze(m[:rest]), 0, m[:ispc]) if m

        Line.new(:piece, ColumnRows.squeeze(raw), ColumnRows.indent(raw))
      end

      # Drop the preface: only the heading directly above the first row is a
      # country.
      def from_table(lines)
        first = lines.index { |l| l.kind == :row }
        return lines unless first

        lines.drop(first.positive? && lines[first - 1].kind == :piece ? first - 1 : first)
      end

      def read(line)
        case line.kind
        when :break then break_run
        when :row then add_row(line)
        else piece(line)
        end
      end

      def break_run
        @row_words = nil
        @open_country = false
      end

      def add_row(line)
        @open_country = false
        @row_words = words(line.text)
        @rows << Row.new(line.ispc, @row_words.sort.join(' '))
      end

      def piece(line)
        if @row_words && line.indent > HEADING_INDENT
          @row_words.concat(words(line.text))
          @rows.last.text = @row_words.sort.join(' ')
        elsif line.indent <= HEADING_INDENT
          heading(line)
        end
      end

      def words(text) = text.scan(/[[:alnum:]]+/)

      def heading(line)
        if @open_country
          last = @rows.last
          last.text = ColumnRows.squeeze("#{last.text} #{line.text}")
          last.key = "country:#{last.text}"
        else
          @rows << Row.new("country:#{line.text}", line.text)
        end
        @open_country = true
        @row_words = nil
      end
    end
  end
end
