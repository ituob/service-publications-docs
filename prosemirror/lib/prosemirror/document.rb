# frozen_string_literal: true

require_relative 'node'

module Prosemirror
  class Document < Node
    def initialize(data = {})
      super(data)
      @type = 'doc'
    end

    def tables
      find_children('table')
    end

    def paragraphs
      find_children('paragraph')
    end

    def first_paragraph
      find_first('paragraph')
    end

    def first_table
      find_first('table')
    end
  end
end
