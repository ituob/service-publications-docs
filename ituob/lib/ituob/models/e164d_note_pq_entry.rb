# frozen_string_literal: true


module Ituob
  module Models
    class E164DNotePQEntry < Entry
      DATASET_CODE = '1114-E.164D-Note-PQ'

      attribute :applicant, :string
      attribute :network, :string
      attribute :cc_ic, :string
      attribute :status, :string, values: %w[Assigned Reserved Spare]
      attribute :formerly, :string
      attribute :notes, :string, collection: true
      attribute :effective_date, :string
    end
  end
end
