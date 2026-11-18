# frozen_string_literal: true

module Ituob
  # Typed views built from replayed register state.
  module Projections
    autoload :PublicationLabels, 'ituob/projections/publication_labels'
    autoload :PublicationDataset, 'ituob/projections/publication_dataset'
    autoload :RegisterItems, 'ituob/projections/register_items'
    autoload :RegisterEdition, 'ituob/projections/register_edition'
    autoload :RegisterLocale, 'ituob/projections/register_locale'
    autoload :KeyHistory, 'ituob/projections/key_history'
    autoload :RegisterActions, 'ituob/projections/register_actions'
  end
end
