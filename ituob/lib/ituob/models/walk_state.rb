# frozen_string_literal: true

module Ituob
  module Models
    # Walk state shared by the paragraph-walk amendment parsers
    # (F32TDI, X121DNIC, ListVIII). Owns the ACTION LIFECYCLE —
    # open/ensure/close over a list of actions — parameterized by the
    # parser's action class. Walk PAYLOAD fields (country, station,
    # pending office, ...) belong to the parser-specific subclasses.
    class WalkState
      attr_accessor :action
      attr_reader :actions, :action_class

      def initialize(action_class:)
        @action_class = action_class
        @actions = []
      end

      # Close the current action (if any) and open a fresh one.
      def open_action
        @actions << @action if @action
        @action = @action_class.new
        @action.entries = []
        @action
      end

      # The current action, opening one if none exists yet.
      def ensure_action
        @action || open_action
      end

      # Flush the current action at end of walk.
      def close
        @actions << @action if @action
        @action = nil
      end
    end
  end
end
