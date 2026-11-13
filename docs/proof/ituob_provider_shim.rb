# frozen_string_literal: true

# TEMPORARY SHIM -- drop once card 127 lands
# (ituob/lib/metanorma/plugin/lutaml/data_providers/ituob.rb), which
# registers the same thing and is discovered by the plugin automatically.
# check_e212_1170.rb loads this file only when "ituob" is not yet registered.
require "ituob"

Metanorma::Plugin::Lutaml::DataProviders.register("ituob") { Ituob::Provider.new }
