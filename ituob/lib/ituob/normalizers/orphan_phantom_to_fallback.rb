# frozen_string_literal: true

module Ituob
  module Normalizers
    # For every (issue × slug) directory whose ONLY files are phantoms,
    # replace them with a single +text.yaml+ carrying the verbatim source
    # ProseMirror content.
    #
    # This preserves content that the parser could not structure.
    class OrphanPhantomToFallback < Base
      def apply_to(issue_id)
        result = Result.new(name: name)
        issue_repository.each_dataset_slug(issue_id) do |slug|
          next if slug == 'general'
          next if Catalogs::MessageTypes.textual?(slug)

          process_dir(issue_id, slug, result)
        end
        result
      end

      private

      def process_dir(issue_id, slug, result)
        action_files = collect_action_files(issue_id, slug)
        return if action_files.empty?

        all_phantom = action_files.all? do |name|
          data = issue_repository.read_change_object(issue_id, slug, name)
          phantom?(data)
        end
        return unless all_phantom

        contents = find_source_contents(issue_id, slug)
        return unless contents

        action_files.each do |name|
          issue_repository.delete_change_object(issue_id, slug, name)
          result.files_deleted += 1
        end

        payload = {
          '_class' => 'TextAmendment',
          'ob_issue_no' => issue_id.to_s,
          'reference' => "OB-#{issue_id}",
          'contents' => contents,
          'note' => 'Converted from orphan phantom action file(s) — parser produced no structured entries',
        }
        issue_repository.write_change_object(issue_id, slug, 'text.yaml', payload)
        result.files_created += 1
        result.issues_affected += 1
        result.details << "OB #{issue_id}/#{slug}: phantoms → text.yaml"
      end

      def collect_action_files(issue_id, slug)
        files = []
        change_object_repository.each_action_file(issue_id, slug) do |_seq, _type, name|
          files << name
        end
        files
      end

      def phantom?(data)
        return false unless data.is_a?(Hash)

        entries = data.dig('data', 'entries')
        return true if entries.is_a?(Array) && entries.empty?
        return true if entries.is_a?(Array) && entries.length == 1 && entries.first.is_a?(Hash) && entries.first.empty?

        false
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
