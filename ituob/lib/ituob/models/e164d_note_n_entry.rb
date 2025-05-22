# frozen_string_literal: true

require_relative 'multilingual_string'
require_relative 'entry'

module Ituob
  module Models
    class E164DNoteNEntry < Entry
      DATASET_CODE = '1114-E.164D-Note-N'

      attribute :network, :string
      attribute :cc_ic, :string
      attribute :status, :string

    end
  end
end
