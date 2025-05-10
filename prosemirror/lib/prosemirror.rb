# frozen_string_literal: true

require_relative "prosemirror/version"
require_relative "prosemirror/node"
require_relative "prosemirror/text"
require_relative "prosemirror/paragraph"
require_relative "prosemirror/hard_break"
require_relative "prosemirror/table"
require_relative "prosemirror/table_row"
require_relative "prosemirror/table_cell"
require_relative "prosemirror/document"
require_relative "prosemirror/parser"

module Prosemirror
  class Error < StandardError; end
  # Your code goes here...
end
