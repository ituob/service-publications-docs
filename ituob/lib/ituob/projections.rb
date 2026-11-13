# frozen_string_literal: true

module Ituob
  # Typed views built from replayed register state.
  module Projections
    autoload :RegisterItems, 'ituob/projections/register_items'
    autoload :RegisterEdition, 'ituob/projections/register_edition'
    autoload :KeyHistory, 'ituob/projections/key_history'
  end
end
