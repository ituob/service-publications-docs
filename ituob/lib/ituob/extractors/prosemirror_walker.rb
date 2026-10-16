# frozen_string_literal: true

module Ituob
  module Extractors
    # Shared utilities for walking ProseMirror doc trees.
    #
    # ProseMirror content is a tree of Hash nodes with +type+ and
    # +content+ keys. Text nodes carry +text+; tables have +table_row+
    # children, which have +table_cell+ children, which have paragraph
    # children.
    module ProseMirrorWalker
      module_function

      # Walk every node in the tree, depth-first. Yield each Hash node.
      def walk(node, &block)
        case node
        when Hash
          yield node
          node.each_value { |v| walk(v, &block) }
        when Array
          node.each { |v| walk(v, &block) }
        end
      end

      # Walk every top-level child of +doc+. Does not recurse.
      def each_top_level(doc)
        return enum_for(:each_top_level, doc) unless block_given?
        return unless doc.is_a?(Hash) && doc['content'].is_a?(Array)

        doc['content'].each { |node| yield node if node.is_a?(Hash) }
      end

      # Find every +table+ node in the tree (depth-first order).
      def each_table(doc)
        return enum_for(:each_table, doc) unless block_given?

        walk(doc) do |node|
          yield node if node.is_a?(Hash) && node['type'] == 'table'
        end
      end

      # Find every +paragraph+ node in the tree.
      def each_paragraph(doc)
        return enum_for(:each_paragraph, doc) unless block_given?

        walk(doc) do |node|
          yield node if node.is_a?(Hash) && node['type'] == 'paragraph'
        end
      end

      # Extract concatenated text from a node (any type).
      def node_text(node)
        parts = []
        walk(node) do |n|
          next unless n.is_a?(Hash)
          next unless n['type'] == 'text'

          parts << n.fetch('text', '')
        end
        parts.join
      end

      # Normalize whitespace in a string.
      def normalize_ws(s)
        return '' unless s

        s.to_s.gsub(/\s+/, ' ').strip
      end

      # Extract rows of cells (each cell is normalized text) from a table.
      def extract_rows(table_node)
        rows = []
        return rows unless table_node.is_a?(Hash) && table_node['content'].is_a?(Array)

        table_node['content'].each do |row_node|
          next unless row_node.is_a?(Hash) && row_node['type'] == 'table_row'

          cells = []
          row_node.fetch('content', []).each do |cell_node|
            next unless cell_node.is_a?(Hash) && cell_node['type'] == 'table_cell'

            cells << normalize_ws(node_text(cell_node))
          end
          rows << cells unless cells.empty?
        end
        rows
      end
    end
  end
end
