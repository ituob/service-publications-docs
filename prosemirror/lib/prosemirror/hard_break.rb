# frozen_string_literal: true

require_relative 'node'

module Prosemirror
  class HardBreak < Node
    def text_content
      "\n"
    end
  end
end
