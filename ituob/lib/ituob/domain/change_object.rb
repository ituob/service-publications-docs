# frozen_string_literal: true

module Ituob
  module Domain
    # An immutable, serializable representation of a single change applied
    # to a dataset by an OB issue.
    #
    # A ChangeObject has:
    # * +action_type+ — one of +Catalogs::ActionTypes.all+
    # * +issue_id+ — the OB IssueId where the change was published
    # * +publication_id+ — the PublicationId being changed
    # * +position_on+ — date the change became effective (optional)
    # * +identifier+ — the RecordCode identifying the affected record
    # * +data+ — a Hash with structured fields parsed from source
    # * +source+ — :parsed, :fallback, :placeholder (provenance)
    class ChangeObject
      attr_reader :action_type, :issue_id, :publication_id,
                  :position_on, :identifier, :data, :source, :note

      def initialize(action_type:, issue_id:, publication_id:,
                     position_on: nil, identifier:, data:,
                     source: :parsed, note: nil)
        @action_type = action_type
        @issue_id = issue_id.is_a?(Identifiers::IssueId) ? issue_id : Identifiers::IssueId.new(issue_id)
        @publication_id = publication_id.is_a?(Identifiers::PublicationId) ? publication_id : Identifiers::PublicationId.new(publication_id)
        @position_on = position_on
        @identifier = identifier
        @data = data.freeze
        @source = source.to_sym
        @note = note
        freeze
      end

      # Filename for serialization: +NNN-ACTION.yaml+.
      def filename(sequence:)
        format('%03d', sequence) + '-' + action_type + '.yaml'
      end

      def to_change_hash
        {
          'type' => action_type,
          'date_requested' => position_on,
          'date_active' => position_on,
          'ob_issue_no' => issue_id.to_s,
          'reference' => "OB-#{issue_id}",
          'identifier' => { 'code' => identifier.to_s },
          'data' => data,
        }.tap do |h|
          h['note'] = note if note
        end
      end

      # +true+ if this ChangeObject carries no entries (a phantom).
      def empty_entries?
        entries = data['entries']
        return true unless entries.is_a?(Array)
        return true if entries.empty?

        entries.length == 1 && entries.first.is_a?(Hash) && entries.first.empty?
      end

      def placeholder?
        source == :placeholder
      end

      def textual_fallback?
        source == :fallback
      end
    end
  end
end
