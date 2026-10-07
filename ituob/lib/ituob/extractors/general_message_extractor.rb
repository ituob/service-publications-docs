# frozen_string_literal: true

module Ituob
  module Extractors
    # Extract a general message from source YAML into the appropriate
    # output location.
    #
    # Output location depends on the type's category (see
    # +Catalogs::MessageTypes+):
    #
    # * +structured+ — emit +general/{type}.yaml+
    # * +textual+ — emit +{type}/NNN.yaml+
    class GeneralMessageExtractor
      attr_reader :issue_id, :message_hash

      def initialize(issue_id:, message_hash:)
        @issue_id = issue_id.is_a?(Domain::Identifiers::IssueId) ? issue_id : Domain::Identifiers::IssueId.new(issue_id)
        @message_hash = message_hash
      end

      def type
        @type ||= message_hash.fetch('type', Catalogs::MessageTypes::UNTYPED)
      end

      # Returns { relative_path:, payload: } describing where to write
      # this message and what to write.
      def extract
        case Catalogs::MessageTypes.category(type)
        when :structured
          {
            relative_path: "general/#{type}.yaml",
            payload: structured_payload,
          }
        when :textual
          {
            relative_path: Catalogs::MessageTypes.relative_path_for(type, sequence: next_sequence),
            payload: textual_payload,
          }
        else
          {
            relative_path: Catalogs::MessageTypes.relative_path_for('no_type', sequence: next_sequence),
            payload: textual_payload,
          }
        end
      end

      private

      def next_sequence
        # Caller decides sequencing by globbing the destination directory.
        # We default to 1; the writer can renumber.
        1
      end

      def structured_payload
        {
          'ob_issue_no' => issue_id.to_s,
          'type' => type,
          'payload' => message_hash.reject { |k, _| k == 'type' },
        }
      end

      def textual_payload
        {
          'ob_issue_no' => issue_id.to_s,
          'type' => type,
          'contents' => message_hash['content'] || message_hash['contents'],
        }.compact
      end
    end
  end
end
