# frozen_string_literal: true

module Ituob
  module Normalizers
    # For every (issue × slug) directory with NO yaml files at all, write a
    # +text.yaml+ carrying the source ProseMirror content.
    #
    # This catches cases where an empty amendment declaration was kept
    # without a placeholder, or where the parser produced no output for a
    # declared amendment with non-empty source.
    class EmptyDirFiller < Base
      def apply_to(issue_id)
        result = Result.new(name: name)
        issue_repository.each_dataset_slug(issue_id) do |slug|
          next if slug == 'general'
          next if Catalogs::MessageTypes.textual?(slug)

          yaml_files = collect_yaml_files(issue_id, slug)
          next unless yaml_files.empty?

          contents = find_source_contents(issue_id, slug)
          next unless contents

          payload = {
            '_class' => 'TextAmendment',
            'ob_issue_no' => issue_id.to_s,
            'reference' => "OB-#{issue_id}",
            'contents' => contents,
            'note' => 'Filled from source ProseMirror content after parser produced no structured actions',
          }
          issue_repository.write_change_object(issue_id, slug, 'text.yaml', payload)
          result.files_created += 1
          result.issues_affected += 1
          result.details << "OB #{issue_id}/#{slug}: empty dir → text.yaml"
        end
        result
      end

      private

      def collect_yaml_files(issue_id, slug)
        files = []
        issue_repository.each_change_object_file(issue_id, slug) do |name, _|
          files << name
        end
        files
      end

      def find_source_contents(issue_id, slug)
        publication = Catalogs::Publications.publication_for(slug)
        return nil unless publication

        source = issue_repository.read_amendments(issue_id)
        return nil unless source.is_a?(Hash) && source['messages'].is_a?(Array)

        source['messages'].each do |msg|
          next unless msg['type'] == 'amendment'
          next unless msg.dig('target', 'publication') == publication

          contents = msg['contents']
          next unless contents.is_a?(Hash)
          return contents['en'] if contents.key?('en')
        end
        nil
      end
    end
  end
end
