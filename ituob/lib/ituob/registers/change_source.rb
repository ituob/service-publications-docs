# frozen_string_literal: true

module Ituob
  module Registers
    # Source of ordered Changes for a register. Implementations read
    # from disk (seed + changes/). Replay calls +each_until(N)+.
    #
    # This is the seam for swapping storage layouts (single-file,
    # per-issue directories, etc.) without touching Replay.
    class ChangeSource
      attr_reader :register_id

      def initialize(register_id:)
        @register_id = register_id.to_s
      end

      # OB issue number of the seed publication, or +nil+ if the
      # source doesn't have a notion of a seed. Concrete sources
      # override.
      def seed_issue
        nil
      end

      # Yield each Change in canonical order (seed first, then
      # subsequent amendments by ob_issue ascending).
      def each_until(ob_issue_limit = nil)
        return enum_for(:each_until, ob_issue_limit) unless block_given?

        each_sorted do |change|
          next if ob_issue_limit && change.ob_issue_no && change.ob_issue_no > ob_issue_limit

          yield change
        end
      end

      # Hook — subclasses override to enumerate changes in canonical order.
      def each_sorted
        raise NotImplementedError, "#{self.class}#each_sorted not implemented"
      end
    end
  end
end
