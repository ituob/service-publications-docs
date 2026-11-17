# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # The PDF publication manifest (pdf/manifest.json): the root the site's
    # loader accepts as { "publications": [...] }. Serialized only through
    # lutaml-model.
    class PublicationManifest < Lutaml::Model::Serializable
      attribute :publications, PublicationManifestEntry, collection: true, initialize_empty: true

      key_value do
        map 'publications', to: :publications, render_empty: true
      end
    end
  end
end
