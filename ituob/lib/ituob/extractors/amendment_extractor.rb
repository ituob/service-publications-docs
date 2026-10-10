# frozen_string_literal: true

module Ituob
  module Extractors
    # Extract ChangeObjects for a single +Domain::Amendment+.
    #
    # Decides which extractor to use based on the publication's
    # classification:
    #
    # * +textual+ — emit a single text.yaml fallback carrying the verbatim
    #   ProseMirror content.
    # * +structured+ — use the generic +ProseMirror+ extractor (which
    #   understands all three observed layouts).
    # * +empty contents+ — emit a placeholder.yaml.
    class AmendmentExtractor
      attr_reader :issue_id, :amendment

      def initialize(issue_id:, amendment:)
        @issue_id = issue_id.is_a?(Domain::Identifiers::IssueId) ? issue_id : Domain::Identifiers::IssueId.new(issue_id)
        @amendment = amendment
      end

      # Returns an Array of ChangeObjects. May be empty if source had no
      # extractable content.
      def extract
        if amendment.empty_contents?
          [placeholder]
        elsif amendment.textual?
          [textual_fallback]
        else
          ProseMirror.new.extract(amendment, issue_id: issue_id)
        end
      end

      private

      def placeholder
        Domain::ChangeObject.new(
          action_type: 'PLACEHOLDER',
          issue_id: issue_id,
          publication_id: amendment.publication_id,
          position_on: amendment.position_on,
          identifier: Domain::Identifiers::RecordCode.new('placeholder'),
          data: {
            '_class' => 'EmptyAmendment',
            'publication' => amendment.publication_id.value,
            'target' => { 'publication' => amendment.publication_id.value },
          },
          source: :placeholder,
          note: 'Amendment declared in source with contents: {} — no content published',
        )
      end

      def textual_fallback
        Domain::ChangeObject.new(
          action_type: 'TEXT',
          issue_id: issue_id,
          publication_id: amendment.publication_id,
          position_on: amendment.position_on,
          identifier: Domain::Identifiers::RecordCode.new('text'),
          data: {
            '_class' => 'TextAmendment',
            'contents' => amendment.contents_en,
          },
          source: :fallback,
          note: 'TextAmendment — inherently freeform publication',
        )
      end
    end
  end
end
