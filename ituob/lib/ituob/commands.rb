# frozen_string_literal: true

# CLI subcommands for the +ituob+ gem.
#
# Each leaf command (e.g. +Dataset+, +Schema+) is autoloaded on
# first reference — never via +require_relative+ or internal
# +require "ituob/..."+.

module Ituob
  module Commands
    # Dataset validation / manifest generation subcommand.
    autoload :Dataset, 'ituob/commands/dataset'

    # Schema validation subcommand.
    autoload :Schema, 'ituob/commands/schema'
  end
end
