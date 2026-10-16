# frozen_string_literal: true

# Parent namespace file for +Ituob::Domain+. Declares leaf autoloads.
#
# Domain value objects are immutable typed wrappers around primitives. They
# give the rest of the codebase semantic types instead of raw strings and
# integers, and centralize validation.

module Ituob
  module Domain
    autoload :Identifiers, 'ituob/domain/identifiers'
    autoload :ChangeObject, 'ituob/domain/change_object'
    autoload :Amendment, 'ituob/domain/amendment'
    autoload :Issue, 'ituob/domain/issue'
    autoload :TextAmendmentContent, 'ituob/domain/text_amendment_content'
    autoload :TelephoneServiceEntry, 'ituob/domain/telephone_service_entry'
    autoload :PlannedIssuesSchedule, 'ituob/domain/planned_issues_schedule'
  end
end
