# frozen_string_literal: true

module Ituob
  module Projections
    # Cumulative replay history through the pinned issue, in replay order.
    class RegisterActions
      def initialize(register:, state:)
        @register = register
        @state = state
      end

      def to_model
        Models::RegisterActions.new(
          provenance: RegisterEdition.provenance(@register, @state),
          changes: @state.history.map { |change| Models::RegisterChange.from_yaml(change.to_yaml) }
        )
      end
    end
  end
end
