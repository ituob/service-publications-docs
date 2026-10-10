# frozen_string_literal: true

module Ituob
  module Normalizers
    # Remove phantom empty-entry action files.
    #
    # A phantom action file has +entries: []+ or +entries: [{}]+. These
    # appear when the parser interprets a table header as a separate
    # action. Two cases:
    #
    # 1. Phantom is followed by a non-phantom file of the same action
    #    type — merge its entries into the phantom, then delete the
    #    sibling. Renumber remaining files.
    # 2. Phantom has no non-phantom sibling — just delete it. (EmptyDirFiller
    #    or OrphanPhantomToFallback will handle the resulting empty dir.)
    class PhantomCleanup < Base
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
        files = collect_action_files(issue_id, slug)
        return if files.empty?

        merged_any = false
        deleted_any = false

        i = 0
        while i < files.length
          current = files[i]
          data = load_yaml(issue_id, slug, current)
          if phantom?(data)
            sibling = find_next_non_phantom(files, i + 1, issue_id, slug, data['type'])
            if sibling
              merge_sibling_into!(issue_id, slug, current, sibling)
              files.delete(sibling)
              result.files_modified += 1
              merged_any = true
            else
              issue_repository.delete_change_object(issue_id, slug, current)
              files.delete_at(i)
              result.files_deleted += 1
              deleted_any = true
              next # don't increment i — we deleted at this index
            end
          end
          i += 1
        end

        if merged_any || deleted_any
          renumber_files(issue_id, slug, files)
          result.issues_affected += 1
          result.details << "OB #{issue_id}/#{slug}: #{result.files_modified} merged, #{result.files_deleted} deleted"
        end
      end

      def collect_action_files(issue_id, slug)
        files = []
        change_object_repository.each_action_file(issue_id, slug) do |_seq, _type, name|
          files << name
        end
        files
      end

      def load_yaml(issue_id, slug, name)
        issue_repository.read_change_object(issue_id, slug, name)
      end

      def phantom?(data)
        return false unless data.is_a?(Hash)

        entries = data.dig('data', 'entries')
        return true if entries.is_a?(Array) && entries.empty?
        return true if entries.is_a?(Array) && entries.length == 1 && entries.first.is_a?(Hash) && entries.first.empty?

        false
      end

      def find_next_non_phantom(files, start_idx, issue_id, slug, action_type)
        idx = start_idx
        while idx < files.length
          name = files[idx]
          data = load_yaml(issue_id, slug, name)
          file_type = name.match(Repositories::ChangeObjectRepository::ACTION_FILE_PATTERN)[2]
          return name if file_type == action_type && !phantom?(data)

          idx += 1
        end
        nil
      end

      def merge_sibling_into!(issue_id, slug, target_name, source_name)
        target = load_yaml(issue_id, slug, target_name) || {}
        source = load_yaml(issue_id, slug, source_name) || {}

        # Take sibling's data.entries and identifier.code (if more specific).
        target['data'] = source['data'] if source['data']
        target['identifier'] = source['identifier'] if source['identifier'] && placeholder_code?(target['identifier'])

        issue_repository.write_change_object(issue_id, slug, target_name, target)
        issue_repository.delete_change_object(issue_id, slug, source_name)
      end

      def placeholder_code?(identifier)
        identifier.is_a?(Hash) && identifier['code'] =~ /\A\d+-\d+\z/
      end

      def renumber_files(issue_id, slug, files)
        # Re-read after merges/deletes, group by action type, renumber.
        groups = Hash.new { |h, k| h[k] = [] }
        files.each do |name|
          m = name.match(Repositories::ChangeObjectRepository::ACTION_FILE_PATTERN)
          next unless m

          groups[m[2]] << name
        end

        groups.each do |action_type, group_files|
          group_files.sort.each_with_index do |old_name, idx|
            new_name = format('%03d', idx + 1) + '-' + action_type + '.yaml'
            next if old_name == new_name

            data = load_yaml(issue_id, slug, old_name)
            issue_repository.delete_change_object(issue_id, slug, old_name)
            issue_repository.write_change_object(issue_id, slug, new_name, data)
          end
        end
      end
    end
  end
end
