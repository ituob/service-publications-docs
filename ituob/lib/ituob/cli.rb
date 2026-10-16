# frozen_string_literal: true

require "thor"

module Ituob
  class Cli < Thor
    desc "dataset SUBCOMMAND ...ARGS", "Dataset validation commands"
    subcommand "dataset", Ituob::Commands::Dataset

    def self.exit_on_failure?
      true
    end
  end
end
