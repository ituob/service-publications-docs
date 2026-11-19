# frozen_string_literal: true

require_relative 'base' if File.exist?(File.join(__dir__, 'base.rb'))
require_relative 'g1_support'

module OfficialPdfComparison
  module Shapes
    # E.180 tones used in national networks. A row is one country block: the
    # country line(s), then a line per tone (name, frequency, cadence). The
    # generated PDF wraps a long tone name onto a second line; the official one
    # does not, so the block text is read per column (names, frequencies,
    # cadences), which does not depend on where a name wraps.
    class ToneList < Base
      PUBLICATIONS = %w[T-SP-E.180-2010].freeze
      CADENCE = /\b(?:on|off)\b|\bcontinu|announcement|\dx/i
      FRAGMENT = /\A(?:-\s*)?(?:[IVX]+,?|\(?\d+\))\z/

      def rows(text)
        blocks = []
        pending = []
        lines = G1Support.body_lines(text)
        lines.each_with_index do |line, i|
          cells = G1Support.cells(line.text)
          if cells.empty?
            # a blank line ends a country name unless a page break follows: the
            # generated PDF can strand a country heading at the foot of a page
            nxt = lines.drop(i + 1).find { |l| !l.text.strip.empty? }
            pending = [] if nxt&.page == line.page
          elsif cells.first.text =~ /\A\d+\z/
            # numbered footnotes and the notification form follow the table; a
            # stray number (a wrapped frequency) inside it is skipped
            break if blocks.any? && cells.size >= 2 && cells[1].text =~ /\A[[:alpha:]]/
          elsif cells.size >= 2 && cells.last.text =~ CADENCE
            cells = split_frequency(cells)
            blocks << { name: pending, tones: [] } if pending.any?
            blocks.last[:tones] << tone(cells) if blocks.any?
            pending = []
          elsif cells.size >= 2
            next
          elsif wrapped_cell?(cells.first, blocks.last)
            tone = blocks.last[:tones].last
            cells.first.start >= tone[:cadence_start] - 3 ? tone[:cadence] += " #{cells.first.text}" : tone[:freq] += " #{cells.first.text}"
          elsif continuation?(cells.first, blocks.last)
            blocks.last[:tones].last[:name] << cells.first.text
          else
            pending = (pending + [cells.first.text]).last(3)
          end
        end
        G1Support.unique_keys(blocks.map { |b| Row.new(key(b), text(b)) })
      end

      def prose_stop(lines, start)
        G1Support.prose_stop(lines, start) do |line, _|
          cells = G1Support.cells(line)
          cells.size >= 2 && cells.last.text =~ CADENCE
        end
      end

      private

      # a name that wraps leaves one space before its frequency: "Tone - 425"
      def split_frequency(cells)
        return cells unless cells.size == 2 && (m = cells[0].text.match(/\A(.*\S)\s(\d[\d+\/x.]*)\z/))

        [G1Support::Cell.new(m[1], cells[0].start), G1Support::Cell.new(m[2], cells[1].start - 6), cells[1]]
      end

      def key(block) = block[:name].join(' ').split.first(2).join(' ')

      # name, frequency and cadence cells of one tone line; a two-cell line
      # holds a frequency when its second cell is numeric, else a cadence
      def tone(cells)
        rest = cells.drop(1).map(&:text)
        if rest.size > 1
          { name: [cells[0].text], freq: rest[0], cadence: rest[1..].join(' '), cadence_start: cells[2].start }
        elsif rest[0] =~ %r{\A[\d+/x. -]+\z}
          { name: [cells[0].text], freq: rest[0], cadence: '', cadence_start: cells[1].start + 30 }
        else
          { name: [cells[0].text], freq: '', cadence: rest[0], cadence_start: cells[1].start }
        end
      end

      def text(block)
        tones = block[:tones]
        [block[:name].join(' '), tones.map { |t| t[:name].join(' ') }.join(' '), tones.map { |t| t[:freq] }.join(' '), tones.map { |t| t[:cadence] }.join(' ')].join(' | ')
      end

      # a one-cell line under a tone line that ends in "-" or starts in lower
      # case completes the tone name wrapped onto a second line
      def continuation?(cell, block)
        block && block[:tones].any? && cell.start < 10 && (cell.text.end_with?('-') || cell.text =~ /\A[[:lower:]]/ || cell.text =~ FRAGMENT || cell.text =~ /\A[-(]/)
      end

      # a frequency or cadence that wrapped onto its own line, under its column
      def wrapped_cell?(cell, block)
        block && block[:tones].any? && cell.start >= 10
      end
    end
  end
end
