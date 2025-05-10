# frozen_string_literal: true

require_relative 'node'

module Prosemirror
  class TableRow < Node
    def cells
      content.select { |node| node.type == 'table_cell' }
    end
  end
end
