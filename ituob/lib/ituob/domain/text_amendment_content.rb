# frozen_string_literal: true

module Ituob
  module Domain
    # An immutable wrapper around a TextAmendment's ProseMirror doc tree.
    #
    # TextAmendment publications (NNP, R_SP_LM.V, R_SP_LN.VIII, BUREAUFAX,
    # RR.25.1, Coast Stations, E212_ICC) carry freeform prose and tables
    # without a per-entry schema. This value object gives every other
    # module (verifiers, renderers, normalizers) a structured view of
    # the content without each one re-parsing the ProseMirror tree.
    #
    # The wrapped Hash is the verbatim `contents.en` ProseMirror doc.
    class TextAmendmentContent
      attr_reader :doc

      def initialize(doc)
        raise TypeError, 'TextAmendmentContent requires a Hash' unless doc.is_a?(Hash)

        @doc = doc.freeze
        freeze
      end

      # Iterate every top-level child of the doc (Hash nodes only).
      def each_top_level_node
        return enum_for(:each_top_level_node) unless block_given?

        content = @doc['content']
        return unless content.is_a?(Array)

        content.each do |node|
          yield node if node.is_a?(Hash)
        end
      end

      # Every Table node in document order.
      def each_table
        return enum_for(:each_table) unless block_given?

        each_top_level_node do |n|
          yield n if n['type'] == 'table'
        end
      end

      # Every Paragraph node in document order.
      def each_paragraph
        return enum_for(:each_paragraph) unless block_given?

        each_top_level_node do |n|
          yield n if n['type'] == 'paragraph'
        end
      end

      # Every Heading node in document order.
      def each_heading
        return enum_for(:each_heading) unless block_given?

        each_top_level_node do |n|
          yield n if n['type'] == 'heading'
        end
      end

      # The first heading's text, or nil if there are no headings.
      def title
        node = each_heading.first
        return nil unless node

        node_text(node)
      end

      # Paragraphs whose text contains an action keyword. These are
      # the "action header" paragraphs that introduce ADD/SUP/REP/LIR
      # entries in the following tables.
      def action_paragraphs
        each_paragraph.each_with_object([]) do |node, acc|
          text = node_text(node)
          action = Catalogs::ActionTypes.find_last_in(text)
          acc << { text: text, action: action } if action
        end
      end

      # Convert a ProseMirror node to plain text by concatenating its
      # child text nodes.
      def node_text(node)
        parts = []
        walk(node) do |n|
          next unless n.is_a?(Hash)
          next unless n['type'] == 'text'

          parts << n.fetch('text', '')
        end
        parts.join
      end

      # Total character count of body text (headings + paragraphs + table cells).
      def body_chars
        sum = 0
        each_heading { |n| sum += node_text(n).length }
        each_paragraph { |n| sum += node_text(n).length }
        each_table do |t|
          rows = t.fetch('content', [])
          rows.each do |row|
            next unless row.is_a?(Hash) && row['type'] == 'table_row'

            row.fetch('content', []).each do |cell|
              next unless cell.is_a?(Hash) && cell['type'] == 'table_cell'

              sum += node_text(cell).length
            end
          end
        end
        sum
      end

      # +true+ if the doc has any table nodes.
      def has_tables?
        each_table.first ? true : false
      end

      private

      def walk(node, &block)
        case node
        when Hash
          yield node
          node.each_value { |v| walk(v, &block) }
        when Array
          node.each { |v| walk(v, &block) }
        end
      end
    end
  end
end
