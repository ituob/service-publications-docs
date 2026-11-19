# frozen_string_literal: true

require_relative 'column_rows'

module OfficialPdfComparison
  module Shapes
    # E.212A and E.218: "Code | Country or Geographical Area | Note" with the
    # list printed twice, numerically then alphabetically (same codes, so the
    # key carries the table: "num:202", "alpha:202"). E.212A ends with a third
    # table of spare-code counts per range ("spare:000-099"). Arabic prints the
    # code at the right-hand end of the line, every other language at the left.
    # Note c adds a fourth table of shared-code networks ("shared:901 03":
    # network and status, in print order).
    # A name that wraps continues on indented lines below its code line.
    class CodeCountry < Base
      PUBLICATIONS = %w[T-SP-E.212A-2017 T-SP-E.218-2017].freeze

      LEFT = /\A(\s*)(\d{3}|\dXX)\s+(\S.*)\z/
      RIGHT = /\A(.*?\S)\s+(\d{3}|\dXX)\z/
      SPARE_LEFT = /\A\s*(\d{3})\s*[-–]\s*(\d{3})\s+(\S.*)\z/
      SPARE_RIGHT = /\A(.*?\S)\s+(\d{3})\s*[-–]\s*(\d{3})\z/
      SHARED = /\A(.*?)\s*\b(901 \d\d)\b\s*(.*)\z/
      SHARED_SWAPPED = /\A(.*?)\s*\b(\d\d) (901)\b\s*(.*)\z/

      def rows(text)
        @rows = []
        @table = 'num'
        @last = -1
        @name_col = nil
        @shared = false
        ColumnRows.clean_lines(text).each { |line| read(line) }
        ColumnRows.unique_keys(@rows)
      end

      private

      def read(line)
        if line.match?(ColumnRows::PAGE_NUMBER) || line.strip.empty?
          @name_col = nil
          @shared = false
        elsif (shared = shared(line))
          @table = 'shared'
          @shared = true
          add(*shared)
        elsif @shared
          wrap_shared(line)
        elsif (spare = spare(line))
          @table = 'spare'
          add(*spare)
          @name_col = nil
        elsif (code, name, col = code_line(line))
          start(code, name, col)
        elsif @name_col && ColumnRows.indent(line) >= @name_col && @rows.last
          @rows.last.text = ColumnRows.squeeze("#{@rows.last.text} #{line}")
        else
          @name_col = nil
        end
      end

      def start(code, name, col)
        value = code.tr('X', '0').to_i
        @table = 'alpha' if @table == 'num' && value < @last
        @last = value
        add("#{@table}:#{code}", name)
        @name_col = col
      end

      def add(key, name) = @rows << Row.new(key, ColumnRows.squeeze(name))

      # Only a line with text on a side of the code is a shared-network row;
      # "901 Shared code" country rows are code lines and match nothing here.
      def shared(line)
        return if @table == 'num'

        if (m = SHARED.match(line))
          key = m[2]
          rest = [m[1], m[3]]
        elsif (m = SHARED_SWAPPED.match(line))
          key = "#{m[3]} #{m[2]}"
          rest = [m[1], m[4]]
        else
          return
        end
        @rtl = line.match?(/\p{Arabic}/)
        @parts = rest.map { |part| ColumnRows.squeeze(part) }.reject(&:empty?)
        ["shared:#{key}", @parts.join(' | ')] unless @parts.empty?
      end

      # A wrapped network name continues the network part of the row: the first
      # one, or the last where the status column is printed first (Arabic).
      def wrap_shared(line)
        i = @rtl ? -1 : 0
        @parts[i] = ColumnRows.squeeze("#{@parts[i]} #{line}")
        @rows.last.text = @parts.join(' | ')
      end

      def spare(line)
        if (m = SPARE_LEFT.match(line))
          ["spare:#{m[1]}-#{m[2]}", m[3]]
        elsif line.match?(/\p{Arabic}/) && (m = SPARE_RIGHT.match(line))
          ["spare:#{m[3]}-#{m[2]}", m[1]]
        end
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
