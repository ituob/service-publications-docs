# frozen_string_literal: true

require "thor"
require "yaml"
require "json-schema"
require "colorize"

module Ituob
  module Commands
    class Schema < Thor
      desc "validate", "Validate YAML files against their schemas"
      option :dataset, type: :string, aliases: "-d", desc: "Dataset to validate"
      option :verbose, type: :boolean, aliases: "-v", desc: "Show verbose output"

      # TODO: Implement!
    end
  end
end
