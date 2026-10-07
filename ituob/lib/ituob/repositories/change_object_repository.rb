# frozen_string_literal: true

module Ituob
  module Repositories
    # Read and write per-issue change-object files.
    #
    # This is a thin facade over IssueRepository for the change-object
    # subset of operations (read/write/list/delete action files).
    class ChangeObjectRepository
      ACTION_FILE_PATTERN = /\A(\d{3})-([A-Z]+)\.yaml\z/

      attr_reader :issue_repository

      def initialize(issue_repository:)
        @issue_repository = issue_repository
      end

      # List all action files for a (issue × slug) pair, parsed into
      # (sequence, action_type, filename) tuples.
      def each_action_file(issue_id, slug)
        return enum_for(:each_action_file, issue_id, slug) unless block_given?

        issue_repository.each_change_object_file(issue_id, slug) do |name, _path|
          next if name == 'text.yaml'
          next if name == 'placeholder.yaml'

          m = ACTION_FILE_PATTERN.match(name)
          next unless m

          yield m[1].to_i, m[2], name
        end
      end

      # +true+ if a text.yaml exists for this (issue × slug) pair.
      def has_text_fallback?(issue_id, slug)
        issue_repository.read_change_object(issue_id, slug, 'text.yaml') != nil
      end

      # +true+ if a placeholder.yaml exists for this (issue × slug) pair.
      def has_placeholder?(issue_id, slug)
        issue_repository.read_change_object(issue_id, slug, 'placeholder.yaml') != nil
      end

      # Load every action file for a (issue × slug) pair as a list of
      # parsed Hashes (with +__file__+ added for traceability).
      def load_action_payloads(issue_id, slug)
        payloads = []
        each_action_file(issue_id, slug) do |_seq, _type, name|
          data = issue_repository.read_change_object(issue_id, slug, name)
          next unless data.is_a?(Hash)

          data['__file__'] = name
          payloads << data
        end
        payloads
      end

      # Delete all action files in a directory.
      def clear_action_files!(issue_id, slug)
        each_action_file(issue_id, slug) do |_seq, _type, name|
          issue_repository.delete_change_object(issue_id, slug, name)
        end
      end
    end
  end
end
