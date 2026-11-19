# frozen_string_literal: true

require_relative 'base'

module OfficialPdfComparison
  module Shapes
    # ITU Telegram Destination Indicators (F.32-2011): telegraph-office table
    # rows, each ending in a 4-character office code. The name is the cell text
    # before the code, plus wrapped continuation lines (see Row and Gap).
    class F32 < Base
      PUBLICATIONS = %w[T-SP-F.32-2011].freeze

      CODE = /\A(?=.*[A-Z])[A-Z0-9-]{4}\z/
      FOOTNOTE = /\A(?:\d+|[a-z])\)\z/
      COLUMN_SLACK = 4
      MAX_SCAN = 6
      FURNITURE = OfficialPdfComparison::FURNITURE
      TABLE_HEADER = OfficialPdfComparison::TABLE_HEADER

      # The lines between two code lines (or between a code line and page
      # furniture) that can be wrap text of one row's name. Each line carries the
      # text it has at the upper row's name column (a) and at the lower row's (b),
      # nil where it does not continue that column. A gap is split between its two
      # rows: the upper row takes the first s lines, the lower row the rest, so a
      # line belongs to exactly one row and none is dropped. valid lists the splits
      # the columns allow.
      Gap = Struct.new(:lines) do
        def valid
          @valid ||= (0..lines.size).select { |s| lines.first(s).all? { |l| l[:a] } && lines.drop(s).all? { |l| l[:b] } }
        end

        def all_text = lines.map { |l| l[:a] || l[:b] }
      end

      # A table row: the code line's name and the gaps above and below it. How a gap
      # is split between its two rows differs between the two PDFs (and a name's
      # first line may sit above or below the code), so a row has one reading of
      # its name per split of its two gaps: the lines it takes above, the code-line
      # text, the lines it takes below, joined. Which split is the right one is
      # settled across rows, see OfficialPdfComparison.consistent_failures.
      Row = Struct.new(:name, :code, :line, :col, :above, :below) do
        def to_s = "#{code} #{name}"

        # Every wrap line of the row's neighbourhood, in reading order.
        def full_name = OfficialPdfComparison.squish((above.all_text + [name] + below.all_text).join(' '))

        def reading(sa, sb)
          OfficialPdfComparison.normalise((above.lines.drop(sa).map { |l| l[:b] } + [name] + below.lines.first(sb).map { |l| l[:a] }).join(' '))
        end

        def splits = above.valid.product(below.valid)

        def readings = @readings ||= splits.map { |sa, sb| reading(sa, sb) }.to_set

        def same_name?(other) = readings.intersect?(other.readings)
      end

      # Rows: a layout line ending in a 4-char office code. The name is whatever
      # precedes the code in its cell, or the previous cell when the code stands
      # alone. Wrapped names continue on neighbouring lines in the same column;
      # they are kept as fragments (see Row).
      def cells_at(line)
        line.rstrip.to_enum(:scan, /\S+(?: \S+)*/).map { [Regexp.last_match[0], Regexp.last_match.begin(0)] }
      end

      def rows(text)
        lines = text.lines.map { |l| l.delete("\f") }
        found = {}
        lines.each_with_index do |line, i|
          cells = cells_at(line)
          next if line =~ FURNITURE || cells.empty?

          m = cells.last[0].match(/(?:\A|\s)((?=[A-Z0-9-]*[A-Z])[A-Z0-9-]{4})(?:\d\)|[a-z]\)?|\*)?\z/)
          next unless m
          next if cells.size == 1 && (m.pre_match.empty? || line[/\A */].size < 20)

          name, col = m.pre_match.empty? ? cells[-2] : [m.pre_match, cells.last[1]]
          found[i] = [squish(name), m[1], col]
        end
        above, below = build_gaps(lines, found)
        found.each_with_index.map do |(i, (name, code, col)), k|
          Row.new(name, code, i + 1, col, above[k], below[k])
        end
      end

      # The gap above and the gap below each row. Two rows with no page furniture or
      # table header between them share the gap between them; a barrier splits it
      # into a trailing gap of the upper row and a leading gap of the lower. Lines
      # more than MAX_SCAN from the row (or rows) they continue are not wrap text.
      def build_gaps(lines, found)
        barriers = header_blocks(lines)
        barrier = ->(j) { lines[j] =~ FURNITURE || barriers.include?(j) }
        idx = found.keys
        above = Array.new(idx.size)
        below = Array.new(idx.size)
        (0..idx.size).each do |k|
          up = idx[k - 1] if k.positive?
          low = idx[k] if k < idx.size
          if up && low && ((up + 1)...low).none? { |j| barrier.call(j) }
            below[k - 1] = above[k] = Gap.new(shared_lines(lines, found, up, low))
          else
            above[k] = Gap.new(edge_lines(lines, found, barrier, low, -1)) if low
            below[k - 1] = Gap.new(edge_lines(lines, found, barrier, up, 1)) if up
          end
        end
        [above, below]
      end

      # Lines between code lines up and low. A cell on a code line itself counts
      # too when it sits at the other row's name column (a name line that shares its
      # line with the next or previous row's code).
      def shared_lines(lines, found, up, low)
        col_up = found[up][2]
        col_low = found[low][2]
        out = foreign_cells(lines, up, found[up]).filter_map { |cells| gap_line(cells, nil, col_low) }
        ((up + 1)...low).each do |j|
          next unless j - up <= MAX_SCAN || low - j <= MAX_SCAN

          out << gap_line(name_cells(lines[j]), col_up, col_low)
        end
        foreign = foreign_cells(lines, low, found[low]).filter_map { |cells| gap_line(cells, col_up, nil) }
        out.compact + foreign + continuation_lines(lines, found, low, col_up, foreign.any?)
      end

      # A name that continues under the lower row's code line (the upper row's name
      # column holds a different cell there): the following lines at that column,
      # up to the first line that has none or is a code line.
      def continuation_lines(lines, found, low, col, started)
        out = []
        j = low + 1
        while started && j < lines.size && (j - low) <= MAX_SCAN && !found.key?(j) && lines[j] !~ FURNITURE
          line = gap_line(name_cells(lines[j]), col, nil) or break
          out << line
          j += 1
        end
        out
      end

      # Lines on one side of a row only (up to a barrier or MAX_SCAN lines): dir 1
      # below the row (a trailing gap), -1 above it (a leading gap).
      def edge_lines(lines, found, barrier, row, dir)
        col = found[row][2]
        out = []
        j = row + dir
        while (j - row).abs <= MAX_SCAN && j >= 0 && j < lines.size && !barrier.call(j) && !found.key?(j)
          out << gap_line(name_cells(lines[j]), dir == 1 ? col : nil, dir == 1 ? nil : col)
          j += dir
        end
        out = out.reverse if dir == -1
        out.compact
      end

      # {a: text at the upper row's column, b: at the lower row's}; nil when it
      # continues neither.
      def gap_line(cells, col_up, col_low)
        a = col_up && column_text(cells, col_up)
        b = col_low && column_text(cells, col_low)
        { a: a, b: b } if a || b
      end

      # The cells of a code line other than its name and code, as one cell list
      # per cell, so each can be tested against the neighbouring row's column.
      def foreign_cells(lines, i, (_, _, col))
        cells = name_cells(lines[i])
        code_col = cells_at(lines[i]).last[1]
        cells.reject { |_, c| c == code_col || (c - col).abs <= COLUMN_SLACK }.map { |cell| [cell] }
      end

      def header_blocks(lines)
        lines.each_index.with_object(Set.new) do |i, set|
          next unless lines[i] =~ TABLE_HEADER

          stop = (i...[i + MAX_SCAN, lines.size].min).find { |k| lines[k] =~ /\A\s*1\s+2\s+3\s+4\s+5\s*\z/ } || i
          set.merge(i..stop)
        end
      end

      def name_cells(line) = cells_at(line).reject { |t, _| t =~ FOOTNOTE }

      def column_text(cells, col)
        here = cells.select { |_, c| (c - col).abs <= COLUMN_SLACK }
        squish(here.map(&:first).join(' ')) unless here.empty?
      end
    end
  end
end
