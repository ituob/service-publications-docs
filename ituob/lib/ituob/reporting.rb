# frozen_string_literal: true

# Parent namespace for reporting.
#
# Reporters take +Verifiers::Base::Result+ instances (or arrays of them)
# and emit human-readable output (YAML, stdout summary).

module Ituob
  module Reporting
    autoload :Report, 'ituob/reporting/report'
  end
end
