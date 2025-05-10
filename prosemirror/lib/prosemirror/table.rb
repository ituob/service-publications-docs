# frozen_string_literal: true

require_relative 'node'

module Prosemirror
  class Table < Node
    def rows
      content.select { |node| node.type == 'table_row' }
    end

    def header_row
      rows.first
    end

    def data_rows
      rows[1..-1] || []
    end

    # Get cell at specific position (skips header)
    def cell_at(row_index, col_index)
      return nil if row_index < 0 || col_index < 0
      data_row = data_rows[row_index]
      return nil unless data_row

      data_row.cells[col_index]
    end
  end
end
