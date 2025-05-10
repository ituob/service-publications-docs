# frozen_string_literal: true

require_relative 'ituob/models'

# Ituob module - main entry point for the gem
module Ituob
end

require 'lutaml/model'
require 'lutaml/model/xml/nokogiri_adapter'

Lutaml::Model::Config.configure do |config|
  config.xml_adapter = Lutaml::Model::Xml::NokogiriAdapter
  config.yaml_adapter_type = :standard_yaml
  config.json_adapter_type = :standard_json # can be one of [:standard_json, :multi_json]
end
