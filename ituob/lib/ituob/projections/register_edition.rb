# frozen_string_literal: true

module Ituob
  module Projections
    # Builds the typed Models::RegisterEdition for a replayed register
    # state: hydrated Entry items, lapsed/deleted membership and the
    # touched-key history, with issue provenance.
    class RegisterEdition
      def self.provenance(register, state)
        Models::ProjectionProvenance.new(
          register_id: register.register_id,
          as_of_issue: state.at_ob_issue,
          seed_issue: register.seed_issue,
          last_change_issue: state.last_issue
        )
      end

      def initialize(register:, state:, items:)
        @register = register
        @state = state
        @items = items
      end

      def to_model
        Models::RegisterEdition.new(
          provenance: self.class.provenance(@register, @state),
          items: @items,
          lapsed_keys: @state.lapsed_keys.to_a.sort,
          deleted_keys: @state.deleted_keys.to_a.sort,
          key_history: key_history
        )
      end

      private

      # Keys follow replay's first-touch order; each key's changes keep
      # their replay order. Only changes a key was really touched by.
      def key_history
        @state.key_history.flat_map do |key, changes|
          KeyHistory.entries(key, changes)
        end
      end
    end
  end
end
