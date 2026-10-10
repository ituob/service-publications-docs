# frozen_string_literal: true

# Parent namespace file for +Ituob::Models+. Declares leaf autoloads.
#
# This file is loaded on the first reference to +Ituob::Models+. Each leaf
# class is then loaded lazily on first reference. Per global rules, no
# +require_relative (forbidden — use autoload)+ is used inside this file or any leaf file.

module Ituob
  module Models
    # Shared base classes
    autoload :WalkState, 'ituob/models/walk_state'
    autoload :Change, 'ituob/models/change'
    autoload :ChangeSet, 'ituob/models/change_set'
    autoload :Entry, 'ituob/models/entry'
    autoload :Amendment, 'ituob/models/amendment'

    # Issue-level models
    autoload :IssueGeneral, 'ituob/models/issue_general'
    autoload :OldIssue, 'ituob/models/old_issue'

    # E.118 (Issuer Identification Numbers)
    autoload :E118Entry, 'ituob/models/e118_entry'
    autoload :E118Action, 'ituob/models/e118_action'
    autoload :E118Amendment, 'ituob/models/e118_amendment'

    # E.164 family
    autoload :E164ACNAmendment, 'ituob/models/e164acn_amendment'
    autoload :E164ACNAction, 'ituob/models/e164acn_action'
    autoload :E164CCAmendment, 'ituob/models/e164cc_amendment'
    autoload :E164DNotePQEntry, 'ituob/models/e164d_note_pq_entry'

    # E.212 family
    autoload :E212MNCAmendment, 'ituob/models/e212mnc_amendment'

    # E.218
    autoload :E218TRCCAmendment, 'ituob/models/e218trcc_amendment'

    # F.32
    autoload :F32TDIAmendment, 'ituob/models/f32tdi_amendment'

    # F.400
    autoload :F400Amendment, 'ituob/models/f400_amendment'

    # M.1400
    autoload :M1400Amendment, 'ituob/models/m1400_amendment'

    # Q.708 family
    autoload :Q708ISPCAmendment, 'ituob/models/q708ispc_amendment'
    autoload :Q708SANCAmendment, 'ituob/models/q708sanc_amendment'

    # T.35
    autoload :T35NAAmendment, 'ituob/models/t35na_amendment'

    # X.121
    autoload :X121DNICAmendment, 'ituob/models/x121dnic_amendment'

    # Freeform / TextAmendment publications
    autoload :RR251Amendment, 'ituob/models/rr251_amendment'
    autoload :TextAmendment, 'ituob/models/text_amendment'

    # National numbering plans — one shared entry model across the
    # DP amendments and the NNP listings.
    autoload :DPAmendment, 'ituob/models/dp_amendment'
    autoload :DPEntry, 'ituob/models/dp_entry'
    autoload :DPAction, 'ituob/models/dp_action'
    autoload :NNPAmendment, 'ituob/models/nnp_amendment'

    # List VIII (coast stations / monitoring stations)
    autoload :ListVIIIAmendment, 'ituob/models/list_viii_amendment'

    # General message types
    autoload :GeneralMessage, 'ituob/models/general_message'
    autoload :GeneralRunningAnnexes, 'ituob/models/general_running_annexes'
    autoload :GeneralApprovedRecommendations, 'ituob/models/general_approved_recommendations'
    autoload :GeneralCallbackProcedures, 'ituob/models/general_callback_procedures'
    autoload :GeneralCustom, 'ituob/models/general_custom'
    autoload :GeneralIpns, 'ituob/models/general_ipns'
    autoload :GeneralIptn, 'ituob/models/general_iptn'
    autoload :GeneralMiscCommunications, 'ituob/models/general_misc_communications'
    autoload :GeneralOrgChanges, 'ituob/models/general_org_changes'
    autoload :GeneralSancs, 'ituob/models/general_sanc'
    autoload :GeneralServiceRestrictions, 'ituob/models/general_service_restrictions'
    autoload :GeneralTelephoneServices, 'ituob/models/general_telephone_service'

    # Data-shape classes compiled from the LML ontology; loaded
    # eagerly because sibling leaf files reference these constants at
    # load time (e.g. ListVIIIAction's entries type).
    autoload :Compiled, 'ituob/models/compiled'
    Compiled.load!
  end
end
