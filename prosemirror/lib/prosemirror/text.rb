# frozen_string_literal: true

require_relative 'node'

module Prosemirror
  class Text < Node
    attr_reader :text

    def initialize(data = {})
      super
      @text = data['text']
    end

    def text_content
      @text || ""
    end
  end
end
