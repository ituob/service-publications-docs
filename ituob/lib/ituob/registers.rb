# frozen_string_literal: true

# ITU OB register / replay model.
#
# A Register is a named dataset mandated by an ITU-T Recommendation.
# Its state at any point in time is a pure projection of an ordered
# patch stream:
#
#   state(N) = empty + (SEED batch expanded as ADDs at seed_issue)
#                     + every OB amendment at issues <= N
#
# All value objects are frozen and Comparable. Strategies (one per
# action type) implement the patch semantics. The Replay service is
# pure and idempotent.
module Ituob
  module Registers
    autoload :ActionType, 'ituob/registers/action_type'
    autoload :Identifier, 'ituob/registers/identifier'
    autoload :Change, 'ituob/registers/change'
    autoload :State, 'ituob/registers/state'
    autoload :StateBuilder, 'ituob/registers/state_builder'
    autoload :StateDiff, 'ituob/registers/state_diff'
    autoload :ChangeSource, 'ituob/registers/change_source'
    autoload :DirectoryChangeSource, 'ituob/registers/directory_change_source'
    autoload :InlineChangeSource, 'ituob/registers/inline_change_source'
    autoload :Replay, 'ituob/registers/replay'
    autoload :SnapshotWriter, 'ituob/registers/snapshot_writer'
    autoload :Strategies, 'ituob/registers/strategies'
  end
end
