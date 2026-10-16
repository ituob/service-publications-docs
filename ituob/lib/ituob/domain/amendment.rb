# frozen_string_literal: true

module Ituob
  module Domain
    # An amendment declaration found in source YAML: a target publication
    # (optionally at a specific position) plus its raw contents.
    class Amendment
      attr_reader :publication_id, :position_on, :contents, :extra

      def initialize(publication_id:, position_on: nil, contents:, **extra)
        @publication_id = publication_id.is_a?(Identifiers::PublicationId) ? publication_id : Identifiers::PublicationId.new(publication_id)
        @position_on = position_on
        @contents = contents
        @extra = extra
      end

      # +true+ if the source +contents+ field was empty (e.g. +{}+).
      def empty_contents?
        return true if contents.nil?
        return true if contents == {}

        contents.is_a?(Hash) && contents.empty?
      end

      # The English ProseMirror doc subtree from contents, or +nil+.
      def contents_en
        return nil unless contents.is_a?(Hash)

        contents['en']
      end

      def slug
        publication_id.slug
      end

      def textual?
        publication_id.textual?
      end

      def structured?
        publication_id.structured?
      end
    end
  end
end
