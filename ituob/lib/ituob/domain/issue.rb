# frozen_string_literal: true

module Ituob
  module Domain
    # A parsed OB Issue — its source declarations plus the output structure
    # produced by extractors/normalizers.
    class Issue
      attr_reader :id, :metadata, :annexes, :general_messages, :amendments

      def initialize(id:, metadata: nil, annexes: nil, general_messages: [], amendments: [])
        @id = id.is_a?(Identifiers::IssueId) ? id : Identifiers::IssueId.new(id)
        @metadata = metadata
        @annexes = annexes
        @general_messages = general_messages
        @amendments = amendments
      end

      # Iterate over each amendment's publication ID.
      def each_publication_id
        return enum_for(:each_publication_id) unless block_given?

        amendments.each do |a|
          yield a.publication_id
        end
      end

      # Iterate over each general message type declared in this issue.
      def each_general_type
        return enum_for(:each_general_type) unless block_given?

        general_messages.each do |m|
          yield m.fetch(:type)
        end
      end
    end
  end
end
