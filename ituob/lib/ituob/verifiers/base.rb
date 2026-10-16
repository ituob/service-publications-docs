# frozen_string_literal: true

module Ituob
  module Verifiers
    # Common interface for all verifiers.
    class Base
      attr_reader :issue_repository

      def initialize(issue_repository: nil)
        @issue_repository = issue_repository
      end

      # Human-readable name for reporting. Override in subclasses.
      def name
        self.class.name.split('::').last
      end

      # Run the verification. Returns a Result.
      def verify
        raise NotImplementedError, "#{self.class}#verify not implemented"
      end

      # A structured verification report.
      Result = Struct.new(
        :name,         # verifier name
        :errors,       # Array<String> — hard failures
        :warnings,     # Array<String> — soft findings
        :stats,        # Hash<any>
        :details,      # Array<Hash> — per-issue breakdown
        keyword_init: true,
      ) do
        def initialize(*args)
          super
          self.errors ||= []
          self.warnings ||= []
          self.stats ||= {}
          self.details ||= []
        end

        def passed?
          errors.empty?
        end

        def merge!(other)
          self.errors += other.errors
          self.warnings += other.warnings
          self.stats = (stats || {}).merge(other.stats || {}) do |_k, a, b|
            a.is_a?(Numeric) && b.is_a?(Numeric) ? a + b : b
          end
          self.details += other.details
          self
        end
      end
    end
  end
end
