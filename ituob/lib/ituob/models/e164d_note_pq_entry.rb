# frozen_string_literal: true

require_relative 'entry'

module Ituob
  module Models
    class E164DNotePQEntry < Entry
      DATASET_CODE = '1114-E.164D-Note-PQ'

      attribute :applicant, :string
      attribute :network, :string
      attribute :cc_ic, :string
      attribute :status, :string, values: %w[Assigned Reserved Spare]
      attribute :formerly, :string
    end
  end
end
