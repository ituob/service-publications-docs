# frozen_string_literal: true

module Ituob
  module Normalizers
    # Orchestrates multiple normalizers in a fixed, idempotent order.
    #
    # The default order is: phantom cleanup → action splitter → action
    # merger → filename canonicalizer → orphan phantom to fallback → empty
    # dir filler → empty amendment placeholder.
    #
    # Running the full pipeline twice produces identical output. This is
    # the property that makes the normalization trustworthy.
    class Pipeline
      DEFAULT_STEPS = [
        FilenameCanonicalizer,
        PhantomCleanup,
        ActionSplitter,
        ActionMerger,
        OrphanPhantomToFallback,
        EmptyDirFiller,
        EmptyAmendmentPlaceholder,
      ].freeze

      attr_reader :steps, :issue_repository

      def initialize(issue_repository:, steps: DEFAULT_STEPS)
        @issue_repository = issue_repository
        @steps = steps
      end

      # Run every step against every issue. Returns an Array of Base::Result.
      def run
        steps.map do |step_class|
          normalizer = step_class.new(issue_repository: issue_repository)
          normalizer.apply_to_all
        end
      end

      # Run a single step against every issue.
      def run_step(step_class)
        step_class.new(issue_repository: issue_repository).apply_to_all
      end
    end
  end
end
