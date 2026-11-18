# frozen_string_literal: true

module Ituob
  module Models
    # Liquid's uniq, equality and pair iteration operate on native values.
    # Serialize the hydrated models, keeping validation and types at the API
    # boundary while preserving the original publication template semantics.
    module PublicationLiquid
      def to_liquid
        to_hash
      end
    end
  end
end
