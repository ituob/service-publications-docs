# frozen_string_literal: true

require_relative 'node'

module Prosemirror
  class Paragraph < Node
    def text_nodes
      content.select { |node| node.type == 'text' }
    end

    def text_content
      result = ""
      content.each do |node|
        if node.type == 'text'
          result += node.text_content
        elsif node.type == 'hard_break'
          result += "\n"
        else
          result += node.text_content
        end
      end
      result
    end
  end
end
