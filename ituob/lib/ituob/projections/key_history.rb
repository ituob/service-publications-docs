# frozen_string_literal: true

module Ituob
  module Projections
    # Builds the typed Models::RegisterKeyHistory for one key of a
    # replayed state, from the changes replay recorded as touching it
    # (State#key_history), never from printed identifiers.
    class KeyHistory
      # Raised when a key was never touched by any change of the register
      # as of the requested issue.
      class UnknownKeyError < ArgumentError; end

      def self.entries(key, changes)
        action_type = Models::Compiled.compiler.compiled_classes.fetch('ActionType')
        changes.map do |change|
          Models::KeyHistoryEntry.new(
            key: key,
            type: action_type.public_send(change.type),
            ob_issue_no: change.ob_issue_no,
            identifier: Models::Identifier.from_hash(change.identifier.to_hash)
          )
        end
      end

      def initialize(register:, state:)
        @register = register
        @state = state
      end

      def for_key(key)
        key = key.to_s
        changes = @state.key_history[key]
        raise UnknownKeyError, unknown_message(key) if changes.nil? && !listed?(key)

        Models::RegisterKeyHistory.new(
          provenance: RegisterEdition.provenance(@register, @state),
          key: key,
          membership: membership(key),
          entries: self.class.entries(key, changes || [])
        )
      end

      private

      def listed?(key)
        @state.entry_for(key) || @state.lapsed?(key) || @state.deleted?(key)
      end

      def membership(key)
        return 'active' if @state.has_key?(key)
        return 'lapsed' if @state.lapsed?(key)
        return 'deleted' if @state.deleted?(key)

        'absent'
      end

      def unknown_message(key)
        "Register #{@register.register_id} has no key #{key.inspect} as of issue #{@state.at_ob_issue}"
      end
    end
  end
end
