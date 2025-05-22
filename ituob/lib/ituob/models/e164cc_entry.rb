# frozen_string_literal: true

require_relative 'multilingual_string'
require_relative 'entry'

module Ituob
  module Models
    class E164CCEntry < Entry
      DATASET_CODE = 'E164_CC'

      attribute :applicant, :string
      attribute :network, :string
      attribute :cc_ic, :string
      attribute :status, :string
      attribute :formerly, :string
    end
  end
end
