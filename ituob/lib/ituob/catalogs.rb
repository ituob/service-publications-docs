# frozen_string_literal: true

# Parent namespace file for +Ituob::Catalogs+. Declares leaf autoloads.
#
# Catalogs are the single source of truth for constants that other code
# needs to look up: which publication IDs exist, which slugs they map to,
# which message types are textual vs structured, which action types are
# valid. Every other module imports from here; no duplicates anywhere.

module Ituob
  module Catalogs
    autoload :YamlCatalog, 'ituob/catalogs/yaml_catalog'
    autoload :Publications, 'ituob/catalogs/publications'
    autoload :Registers, 'ituob/catalogs/registers'
    autoload :Recommendations, 'ituob/catalogs/recommendations'
    autoload :MessageTypes, 'ituob/catalogs/message_types'
    autoload :ActionTypes, 'ituob/catalogs/action_types'
  end
end
