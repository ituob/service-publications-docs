# frozen_string_literal: true


module Ituob
  module Models
    class E164DNoteOEntry < Entry
      DATASET_CODE = '1114-E.164D-Note-O'

      attribute :applicant, :string
      attribute :network, :string
      attribute :cc_ic, :string
      attribute :status, :string
      attribute :formerly, :string

    end
  end
end
