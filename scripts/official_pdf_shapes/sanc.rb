# frozen_string_literal: true

require_relative 'column_rows'

module OfficialPdfComparison
  module Shapes
    # Q.708A: "Code | Geographical Area or Signalling Network" with codes
    # N-NNN (SANC). Arabic prints the code at the right-hand end of the line,
    # every other language at the left. A name that wraps continues on the
    # indented lines below its code line. The list is printed twice (numeric,
    # then by country: keys "num:2-000", "alpha:2-000"); a repeated code gets
    # "#2".
    class Sanc < Base
      PUBLICATIONS = %w[T-SP-Q.708A-2017].freeze

      LEFT = /\A(\s*)(\d-\d{3})\s+(\S.*)\z/
      RIGHT = /\A(.*?\S)\s+(\d-\d{3})\z/

      def rows(text)
        @rows = []
        @name_col = nil
        @table = 'num'
        @last = -1
        ColumnRows.clean_lines(text).each { |line| read(line) }
        ColumnRows.unique_keys(@rows)
      end

      private

      def read(line)
        if line.match?(ColumnRows::PAGE_NUMBER) || line.strip.empty?
          @name_col = nil
        elsif (code, name, col = code_line(line))
          add(code, ColumnRows.squeeze(name))
          @name_col = col
        elsif @name_col && ColumnRows.indent(line) >= @name_col
          @rows.last.text = ColumnRows.squeeze("#{@rows.last.text} #{line}")
        else
          @name_col = nil
        end
      end

      def add(code, name)
        value = code.delete('-').to_i
        @table = 'alpha' if @table == 'num' && value < @last
        @last = value
        key = "#{@table}:#{code}"
        last = @rows.last
        repeat = @page_break && last && last.key == key && last.text == name
        @rows << Row.new(key, name) unless repeat
      end

      def code_line(line)
        if line.match?(/\p{Arabic}/)
          (m = RIGHT.match(line)) && [m[2], m[1], nil]
        elsif (m = LEFT.match(line))
          [m[2], m[3], m[1].size + m[2].size + 1]
        end
      end
    end
  end
end
