# frozen_string_literal: true

module Ituob
  module Registers
    # In-memory ChangeSource. Holds a fixed list of Changes and yields
    # them in canonical (sorted) order on demand.
    #
    # The minimal concrete adapter — useful for tests, programmatic
    # register construction, and any pipeline that already has its
    # changes in memory. The second adapter for the +ChangeSource+
    # contract after +DirectoryChangeSource+.
    #
    # The +seed_issue+ accessor returns the +ob_issue_no+ of the first
    # SEED-typed change in the list, or +nil+ if there isn't one.
    class InlineChangeSource < ChangeSource
      attr_reader :changes

      def initialize(register_id:, changes:)
        super(register_id: register_id)
        @changes = changes.sort
      end

      def seed_issue
        seed = @changes.find(&:seed?)
        seed&.ob_issue_no
      end

      def each_sorted
        return enum_for(:each_sorted) unless block_given?

        @changes.each { |c| yield c }
      end
    end
  end
end
