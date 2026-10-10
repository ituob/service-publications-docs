# frozen_string_literal: true

module Ituob
  module Extractors
    # Common interface for extractors.
    #
    # An extractor takes a +Domain::Amendment+ (or general message hash) and
    # produces an Array of +Domain::ChangeObject+ instances.
    #
    # Subclasses must implement +extract+.
    class Base
      def extract(_amendment)
        raise NotImplementedError, "#{self.class}#extract not implemented"
      end

      protected

      # Build a ChangeObject with provenance = :parsed.
      def build_change_object(action_type:, issue_id:, amendment:, entries:, position_on: nil, note: nil)
        Domain::ChangeObject.new(
          action_type: action_type,
          issue_id: issue_id,
          publication_id: amendment.publication_id,
          position_on: position_on || amendment.position_on,
          identifier: Domain::Identifiers::RecordCode.new("#{issue_id}-000"),
          data: { '_class' => self.class.name, 'entries' => entries },
          source: :parsed,
          note: note,
        )
      end
    end
  end
end
