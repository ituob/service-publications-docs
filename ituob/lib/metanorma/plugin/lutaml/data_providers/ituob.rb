# frozen_string_literal: true

# Discovery file for metanorma-plugin-lutaml: the plugin finds this through
# Gem.find_files on the first `lutaml_data` use of the "ituob" provider and
# requires it. ituob never depends on the plugin; the plugin is already
# loaded when this file runs, and registration is lazy (the factory runs on
# first query, so the data root is resolved then).
#
# Liquid must be loaded before the ituob models so lutaml-model builds
# their Liquid drops; the plugin renders through Liquid, so it is.
require 'liquid'
require 'ituob'

Metanorma::Plugin::Lutaml::DataProviders.register('ituob') do
  Ituob::Provider.new
end
