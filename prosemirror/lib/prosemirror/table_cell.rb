# frozen_string_literal: true

require_relative 'node'

module Prosemirror
  class TableCell < Node
    def paragraphs
      content.select { |node| node.type == 'paragraph' }
    end

    def text_content
      paragraphs.map(&:text_content).join("\n")
    end

    def lines
      text_content.split("\n").map(&:strip).reject(&:empty?)
    end
  end
end
