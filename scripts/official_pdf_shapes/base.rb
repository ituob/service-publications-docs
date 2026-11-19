# frozen_string_literal: true

require 'set'

module OfficialPdfComparison
  # Page furniture and the table header that every Service Publication shares.
  FURNITURE = /\A\s*Annex to ITU OB|\A\s*Service Publication Annex|\A\s*ITUPublications/
  # The table header row, per language (E: Country / geographical area, F: Pays /zone
  # géographique, S: País / zona geográfica).
  TABLE_HEADER = %r{Country\s*/\s*(?:[Gg]eographical|Network)|Pays\s*/\s*zone|Pa[ií]s\s*/\s*zona}
  LIST_MARKER = /\A\s*(?:\d+\.|[a-z]\))\s+/

  # A shape knows how to cut one family of publications into table rows (see
  # docs/pdf/official-comparison-shapes.adoc). Subclasses live one per file in
  # scripts/official_pdf_shapes/ and are found by OfficialPdfComparison.shape.
  module Shapes
    # One table row as the comparator sees it: a key (the thing rows align on,
    # e.g. an office code) and the row's text. Shapes whose names wrap over lines
    # may use their own row class with the same interface (see F32::Row).
    Row = Struct.new(:key, :text) do
      def code = key
      def name = text
      def above = nil
      def below = nil
      def to_s = "#{key} #{text}"
      def full_name = OfficialPdfComparison.squish(text)
      def splits = [[0, 0]]
      def reading(_above, _below) = OfficialPdfComparison.normalise(text)
      def readings = @readings ||= Set[reading(0, 0)]
      def same_name?(other) = readings.intersect?(other.readings)
    end

    # Abstract shape: subclasses implement #rows and list PUBLICATIONS.
    class Base
      # The word that opens the preface in each language of the official PDFs
      # (measured from T-SP-F.32-2011-{E,F,S}.pdf with pdftotext -layout).
      PROSE_MARKERS = {
        'E' => 'Note from TSB',
        'F' => 'Note du TSB',
        'S' => 'Nota de la TSB'
      }.freeze

      PUBLICATIONS = [].freeze

      def self.publications = const_get(:PUBLICATIONS)

      def self.shape_name = name.split('::').last

      def prose_marker(lang) = PROSE_MARKERS[lang.to_s.upcase]

      # Index of the first preface line; 0 when the language has no marker or
      # the marker is absent. A shape may override this.
      def prose_start(lines, lang)
        marker = prose_marker(lang)
        (marker && lines.index { |l| l.strip == marker }) || 0
      end

      # Index where the preface ends (exclusive): the first table header after
      # start, else the end of the text. A shape whose table header differs
      # from F.32's overrides this so table rows are not also compared as prose.
      def prose_stop(lines, start)
        lines.index.with_index { |l, i| i > start && l =~ OfficialPdfComparison::TABLE_HEADER } || lines.size
      end

      # Array of Row, one per table row, in reading order.
      def rows(_text) = raise(NotImplementedError, "#{self.class} must implement #rows")

      private

      def squish(str) = OfficialPdfComparison.squish(str)
      def normalise(str) = OfficialPdfComparison.normalise(str)
    end
  end
end
