# frozen_string_literal: true

require 'set'
require_relative 'base'
require_relative 'g4_text'

module OfficialPdfComparison
  module Shapes
    # RR 25.1 amateur-station annex, two tables:
    #   1. Administration | permitted x | forbidden x | remark note | pages
    #      One row per administration (key = name without dot leaders, text =
    #      which column the x is in, whether a remark note is given, pages).
    #      A name wraps over two lines, the other cells may sit on either.
    #   2. Form of call signs, one block per administration, as free text.
    #      Key = "forms: <administration>", text = the block's words joined.
    class RR251 < Base
      include G4Prose

      PUBLICATIONS = %w[T-SP-RR.25.1-2018].freeze
      NUMBERED = /\A\d+\.\d+\.\s+(.+)\z/
      NUMBERS = /\A\s*1\s+2\s+3\s+4\s+5\s*\z/
      NOTE = /\A(?:\d+|[a-z])\)\z/
      PAGES = /\A\d+(?:\s*[-–,]\s*\d+)*\z/
      PART2_TITLE = /\A\s*[[:upper:]' ’]{30,}\z/
      TOKEN_ORDER = %w[permitted forbidden note pages].freeze
      OPEN_END = /(?:\b(?:and|of|the|et|de|du|des|y|del|la|los|las|gran)|[,-])\z/i

      def rows(text)
        lines = G4Text.lines_of(text)
        split = part2_start(lines)
        part1(lines.first(split)) + part2(lines.drop(split))
      end

      private

      # Part 2 opens at the first heading of the call-sign forms: the numbered
      # "2." heading of the generated PDF, or the all-caps page title of the
      # official one (the part 1 running title has "(RR 25.1)" in it).
      def part2_start(lines)
        from = lines.index { |l| l.match?(NUMBERS) } || 0
        idx = lines.each_index.find { |i| i > from && (lines[i].match?(/\A2\.\s+\S/) || lines[i].match?(PART2_TITLE)) }
        idx || lines.size
      end

      def part1(all)
        rule = all.index { |l| l.match?(/\A\s*_{5,}/) } || all.size
        lines = all.first(rule)
        header = lines.find { |l| l.match?(/\S\s{2,}\S+\s{2,}\S/) && l =~ /(Permit|Permis)/ }
        forbidden_col = header && forbidden_column(header)
        out = []
        cells = [] # the non-name cells of each row, in any line order
        skip = header_lines(lines)
        lines.each_with_index do |line, i|
          take(out, cells, line, forbidden_col) unless skip.include?(i) || line.strip.empty?
        end
        out.zip(cells) { |row, toks| row.text = toks.grep(String).sort_by { |t| TOKEN_ORDER.index(t.split.first) || 9 }.join(' ') }
        out + footnotes(all.drop(rule + 1))
      end

      # The remark text under the rule, without its "1)" / "a)" marker.
      def footnotes(lines)
        words = lines.reject { |l| G4Text.furniture?(l) }.map { |l| l.sub(/\A\s*(?:\d+|[a-z])\)\s+/, '') }.join(' ')
        words.strip.empty? ? [] : [Row.new('remark note', G4Text.squish(words))]
      end

      # Page furniture and the column header that follows it, which the official
      # PDF repeats on every page and the generated one only on the first.
      def header_lines(lines)
        first = lines.index { |l| l.match?(NUMBERS) } || -1
        skip = Set.new(0..first)
        lines.each_index do |i|
          next unless G4Text.furniture?(lines[i])

          skip << i
          nums = ((i + 1)..[i + 12, lines.size - 1].min).find { |j| lines[j].match?(NUMBERS) }
          skip.merge(i..nums) if nums
        end
        skip
      end

      # The column where the second of the two x columns' header word starts.
      def forbidden_column(header)
        words = header.to_enum(:scan, /\S+/).map { Regexp.last_match.begin(0) }
        words[words.size >= 3 ? -2 : -1]
      end

      # Feeds one line to the row being built: a name fragment either opens a
      # row or continues the previous name; the other cells go to the current row.
      def take(out, cells, line, forbidden_col)
        found = line.to_enum(:scan, /\S+(?: \S+)*/).map { [Regexp.last_match[0], Regexp.last_match.begin(0)] }
        first, col = found.first
        rest = found
        if col < 20 && !first.match?(NOTE) && !first.match?(PAGES) && first != 'x'
          fragment = G4Text.squish(first.sub(/[\s.]*\z/, ''))
          rest = found.drop(1)
          if out.any? && continuation?(out.last, cells.last, fragment, rest.empty?)
            glue = out.last.key.end_with?('-') ? '' : ' '
            out.last.key = G4Text.squish("#{out.last.key}#{glue}#{fragment}")
            cells.last << :tail
          else
            out << Row.new(fragment, '')
            cells << []
          end
        elsif out.any? && found.any? { |t, _| t == 'x' }
          cells.last << :split # the x sits on a line of its own, between name lines
        end
        cells.last.concat(tokens(rest, forbidden_col)) if out.any?
      end

      # A fragment continues the previous name when that name is open, when it
      # starts like a tail (lowercase, "(" or closes a paren), or when it stands
      # alone under a name whose x was on a line of its own.
      def continuation?(row, row_cells, fragment, alone)
        return true if open?(row.key) || fragment.match?(/\A[a-z(]/) || fragment.count(')') > fragment.count('(')

        alone && row_cells.include?(:split) && !row_cells.include?(:tail)
      end

      def open?(name)
        name.count('(') > name.count(')') || name.match?(OPEN_END)
      end

      def tokens(cells, forbidden_col)
        cells.map do |t, c|
          if t == 'x' then forbidden_col && c >= forbidden_col - 3 ? 'forbidden' : 'permitted'
          elsif t.match?(NOTE) then 'note'
          elsif t.match?(PAGES) then "pages #{t.delete(' ')}"
          else t
          end
        end
      end

      def part2(lines)
        out = []
        numbered = lines.any? { |l| l.match?(NUMBERED) }
        lines.each_with_index do |line, i|
          next if G4Text.furniture?(line) || line.match?(PART2_TITLE) || line.match?(/\A\s*\(See cont\.\)\s*\z/)

          title = heading(lines, i, line, numbered)
          if title
            out << Row.new("forms: #{title}", '') unless out.any? && out.last.key == "forms: #{title}"
          elsif out.any? && !line.strip.empty?
            out.last.text = G4Text.squish("#{out.last.text} #{line}")
          end
        end
        out
      end

      # "2.3.  Name" (generated PDF) or, when the PDF has no such numbers, a
      # name alone on a line between blank lines (official PDF).
      def heading(lines, idx, line, numbered)
        return (m = line.match(NUMBERED)) && clean(m[1]) if numbered
        return nil unless line.match?(/\A[[:upper:]](?:[^:\s]| (?! )){1,80}\z/) && !open?(line) && (idx.zero? || lines[idx - 1].strip.empty?)
        return nil unless lines[idx + 1].to_s.strip.empty? || lines[idx + 1].match?(/\A\s*\S[^:]{0,40}:\s{2,}/)

        clean(line)
      end

      def clean(title) = G4Text.squish(title.sub(/\s*\((?:continued|suite|continuación)\)\z/i, ''))
    end
  end
end
