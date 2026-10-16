# frozen_string_literal: true

module Ituob
  module Verifiers
    # Cross-reference every change object to its containing issue and every
    # dataset directory to the expected files.
    class ReferenceVerifier < Base
      REQUIRED_DATASET_FILES = %w[metadata.yaml schema-data.yaml].freeze

      def initialize(issue_repository:, dataset_repository:)
        super(issue_repository: issue_repository)
        @dataset_repository = dataset_repository
      end

      def verify
        result = Result.new(name: name)
        result.stats[:datasets_seen] = 0
        result.stats[:ob_issues_seen] = 0
        result.stats[:change_objects_seen] = 0

        verify_datasets(result)
        verify_ob_issues(result)
        verify_change_objects(result)
        result
      end

      private

      def verify_datasets(result)
        @dataset_repository.each_slug do |slug|
          result.stats[:datasets_seen] += 1
          REQUIRED_DATASET_FILES.each do |required|
            path = File.join(@dataset_repository.root, slug, required)
            next if File.file?(path)

            result.errors << "datasets/#{slug}: missing #{required}"
          end
          data_yaml = File.join(@dataset_repository.root, slug, 'data.yaml')
          has_data = File.file?(data_yaml) || Dir.exist?(File.join(@dataset_repository.root, slug, 'data'))
          result.errors << "datasets/#{slug}: missing data.yaml or data/" unless has_data
        end
      end

      def verify_ob_issues(result)
        issue_repository.each_output_issue_id do |iid|
          result.stats[:ob_issues_seen] += 1
          meta_path = File.join(issue_repository.output_root, iid.to_s, 'meta.yaml')
          result.errors << "ob-issues/#{iid}: missing meta.yaml" unless File.file?(meta_path)
        end
      end

      def verify_change_objects(result)
        issue_repository.each_output_issue_id do |iid|
          issue_repository.each_dataset_slug(iid) do |slug|
            issue_repository.each_change_object_file(iid, slug) do |name, _|
              next if name == 'text.yaml'
              next if name == 'placeholder.yaml'

              data = issue_repository.read_change_object(iid, slug, name)
              next unless data.is_a?(Hash)
              next unless data['type'] && data['identifier'] && data['data']

              result.stats[:change_objects_seen] += 1
              ref_iid = data['ob_issue_no'].to_s
              next if ref_iid == iid.to_s

              result.errors <<
                "ob-issues/#{iid}/#{slug}/#{name}: ob_issue_no '#{ref_iid}' != dir id"
            end
          end
        end
      end
    end
  end
end
