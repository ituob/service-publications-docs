# frozen_string_literal: true

module Ituob
  module Normalizers
    # Common interface for all normalizers.
    #
    # A normalizer reads +Domain::Amendment+ and writes ChangeObjects back
    # to disk. Subclasses implement +#apply_to(issue_id)+ which uses
    # +issue_repository+ and +change_object_repository+ for I/O.
    class Base
      attr_reader :issue_repository, :change_object_repository

      def initialize(issue_repository:, change_object_repository: nil)
        @issue_repository = issue_repository
        @change_object_repository = change_object_repository ||
          Repositories::ChangeObjectRepository.new(issue_repository: issue_repository)
      end

      # Human-readable name for reporting. Override in subclasses.
      def name
        self.class.name.split('::').last
      end

      # Apply this normalizer to a single issue. Returns a Result.
      def apply_to(_issue_id)
        raise NotImplementedError, "#{self.class}#apply_to not implemented"
      end

      # Apply to every issue in the repository. Returns aggregate Result.
      def apply_to_all
        aggregate = Result.new(name: name)
        issue_repository.each_output_issue_id do |iid|
          aggregate.merge!(apply_to(iid))
        end
        aggregate
      end

      # Struct recording what a normalizer did.
      Result = Struct.new(
        :name,               # normalizer name
        :issues_affected,    # Integer
        :files_modified,     # Integer
        :files_deleted,      # Integer
        :files_created,      # Integer
        :details,            # Array<String> (sample messages)
        keyword_init: true,
      ) do
        def initialize(*args)
          super
          self[:issues_affected] ||= 0
          self[:files_modified] ||= 0
          self[:files_deleted] ||= 0
          self[:files_created] ||= 0
          self[:details] ||= []
        end

        def merge!(other)
          self.issues_affected += other.issues_affected
          self.files_modified += other.files_modified
          self.files_deleted += other.files_deleted
          self.files_created += other.files_created
          self.details.concat(other.details).uniq!
          self
        end

        def empty?
          issues_affected.zero? && files_modified.zero? && files_deleted.zero? && files_created.zero?
        end
      end
    end
  end
end
