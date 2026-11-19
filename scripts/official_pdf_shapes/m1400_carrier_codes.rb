# frozen_string_literal: true

require_relative 'base'
require_relative 'g3_support'

module OfficialPdfComparison
  module Shapes
    # T-SP-M.1400-2014: the list of ITU carrier codes. A row is one company: a
    # country cell ("Albania (Republic of) / ALB", wrapping over up to four
    # lines at the left margin), the company name and address, the carrier code
    # and the contact lines. The cells of a row interleave line by line in the
    # layout text and wrap differently in each renderer, so a row is the bag of
    # its words (see G3Support.word_bag), keyed by the ISO 3166 alpha-3 code of
    # its country cell. Rows are returned in reading order; a country with
    # several companies has several rows with the same key.
    #
    # Left-to-right layouts only (E, F, S, R, C). The Arabic layout prints the
    # country cell at the right margin, which this shape does not read.
    class M1400CarrierCodes < Base
      PUBLICATIONS = %w[T-SP-M.1400-2014].freeze

      # Prints the readable joined lines, compares the bag of words.
      class BagRow < Row
        def reading(_above, _below) = G3Support.word_bag(text)
      end

      COUNTRY_START = %r{\s/\z|\s/\s?[A-Z]{3}\z}
      # The ISO code ends the country cell, or the renderer ran the next cell
      # into it with one space ("Barbados / BRB Cable and Wireless").
      MARGIN = 4
      ISO = %r{/\s?([A-Z]{3})\b|\A([A-Z]{3})(?:\s|\z)}
      HEADER = /\A(?:Country or area|Pays ou zone|País o zona|Страна или зона|国家或区域|Note\b|Nota\b|NOTE\b|NOTA\b|Примечание|ПРИМЕЧАНИЕ|注)/
      TITLE = /List of ITU Carrier Codes|Liste des codes de transporteur|Lista de códigos de operador|Список кодов МСЭ|国际电联电信运营商代码/i

      # Base's table header is F.32's ("Country / geographical area"); here it is
      # "Country or area". Without this override the whole table is prose and the
      # word diff over ~35k words per side runs out of memory (3.3 GB, measured).
      PROSE_END = /\A\s*(?:Country or area|Pays ou zone|País o zona)\b/

      def prose_stop(lines, start)
        lines.index.with_index { |l, i| i > start && l.match?(PROSE_END) } || lines.size
      end

      def rows(text)
        pages = text.split("\f")
        last = pages.rindex { |p| p.lines.any? { |l| country_cell(l)&.match?(COUNTRY_START) } }
        return [] unless last

        blocks = []
        done = true
        started = false
        in_header = false
        pages.first(last + 1).each do |page|
          G3Support.lines(page).each do |line|
            next if line.strip.empty? || G3Support.furniture?(line) || line.match?(TITLE)

            cell = country_cell(line)
            started ||= cell&.match?(COUNTRY_START)
            next unless started

            if cell&.match?(HEADER)
              in_header = true
              next
            end
            next if in_header && !cell && header_words?(line)

            in_header = false
            if cell
              blocks << { country: [], lines: [] } if done
              blocks.last[:country] << cell
              done = iso_of(cell) ? true : false
            end
            blocks.last&.[](:lines)&.push(line)
          end
        end
        blocks.filter_map { |b| row(b) }
      end

      private

      def country_cell(line)
        # Some official pages are indented by three spaces; the next cell
        # starts at column 25 or later.
        cell, col = G3Support.cells_at(line).first
        cell if cell && col <= MARGIN
      end

      # The wrapped tail of the column header ("Code", "(carrier code)", "de la
      # empresa"). A row that a page break splits continues right after the
      # header, so only header vocabulary is dropped, not every cell-less line.
      HEADER_WORDS = %w[code carrier company contact de la societe société empresa codigo código le les of contacto].freeze

      def header_words?(line)
        words = line.downcase.scan(/[[:alpha:]]+/)
        words.any? && words.all? { |w| HEADER_WORDS.include?(w) }
      end

      def iso_of(cell)
        m = cell.match(ISO)
        m && (m[1] || m[2])
      end

      def row(block)
        iso = block[:country].filter_map { |c| iso_of(c) }.last
        iso && BagRow.new(iso, G3Support.squish(block[:lines].join(' ')))
      end
    end
  end
end
