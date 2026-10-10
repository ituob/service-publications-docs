# frozen_string_literal: true

module Ituob
  module Normalizers
    # Merge consecutive action files with the same type and the same
    # +identifier.code+ into a single file.
    #
    # Counterpart to +ActionSplitter+. The parser sometimes over-segments
    # a single logical action (e.g. one LIR per country into 5 files).
    # This normalizer coalesces them back when the identifier matches.
    class ActionMerger < Base
      PLACEHOLDER_CODE_REGEX = /\A\d+-\d+\z/.freeze

      def apply_to(issue_id)
        result = Result.new(name: name)
        issue_repository.each_dataset_slug(issue_id) do |slug|
          next if slug == 'general'
          next if Catalogs::MessageTypes.textual?(slug)

          merge_dir(issue_id, slug, result)
        end
        result
      end

      private

      def merge_dir(issue_id, slug, result)
        groups = Hash.new { |h, k| h[k] = [] }
        change_object_repository.each_action_file(issue_id, slug) do |_seq, action_type, name|
          data = load(issue_id, slug, name)
          next unless data.is_a?(Hash)

          key = grouping_key(action_type, data)
          groups[key] << name
        end

        merges_needed = groups.count { |_k, names| names.length > 1 }
        return if merges_needed.zero?

        groups.each do |key, names|
          next if names.length == 1

          action_type = key.to_s.split('|', 2).first
          merged_entries = []
          sample_data = nil
          names.each do |n|
            d = load(issue_id, slug, n)
            next if d.nil?

            sample_data ||= d
            merged_entries.concat(d.dig('data', 'entries') || [])
          end
          next if sample_data.nil?

          sample_data['data']['entries'] = merged_entries

          change_object_repository.clear_action_files!(issue_id, slug)
          new_name = format('%03d', 1) + '-' + action_type + '.yaml'
          issue_repository.write_change_object(issue_id, slug, new_name, sample_data)
          result.files_modified += names.length
        end
        result.issues_affected += 1
        result.details << "OB #{issue_id}/#{slug}: merged #{merges_needed} groups"
      end

      def grouping_key(action_type, data)
        code = data.dig('identifier', 'code').to_s
        normalized = PLACEHOLDER_CODE_REGEX.match?(code) ? '_placeholder_' : code
        "#{action_type}|#{normalized}"
      end

      def load(issue_id, slug, name)
        issue_repository.read_change_object(issue_id, slug, name)
      end
    end
  end
end
