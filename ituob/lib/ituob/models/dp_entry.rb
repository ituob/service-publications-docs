# frozen_string_literal: true

module Ituob
  module Models
    # The DP (national numbering plan) dataset prints the full
    # 7-column plan row; the fields live on the shared
    # NumberingPlanEntry.
    class DPEntry < NumberingPlanEntry
      DATASET_CODE = 'DP'
    end
  end
end
