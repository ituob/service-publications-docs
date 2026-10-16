# frozen_string_literal: true

module Ituob
  module Normalizers
    # Split a single action file containing entries of mixed action types
    # into separate per-type files.
    #
    # The parser sometimes emits one +001-ADD.yaml+ containing entries
    # whose +country_or_area.en+ field embeds a different action keyword
    # (e.g. +"Norway SUP"+). This normalizer detects such entries and
    # routes them to a per-type file.
    class ActionSplitter < Base
      def apply_to(issue_id)
        result = Result.new(name: name)
        issue_repository.each_dataset_slug(issue_id) do |slug|
          next if slug == 'general'
          next if Catalogs::MessageTypes.textual?(slug)

          split_dir(issue_id, slug, result)
        end
        result
      end

      private

      def split_dir(issue_id, slug, result)
        groups = Hash.new { |h, k| h[k] = [] }
        source_contents = nil
        change_object_repository.each_action_file(issue_id, slug) do |_seq, file_type, name|
          data = load(issue_id, slug, name)
          next unless data.is_a?(Hash)

          # Preserve the source ProseMirror doc from the first file that
          # has it, so the renderer can fall back to it.
          source_contents ||= data.dig('data', 'source_contents')

          data.dig('data', 'entries')&.each do |entry|
            detected = detect_action_type(entry) || file_type
            groups[detected] << clean_entry(entry, detected)
          end
        end

        return if groups.length <= 1

        change_object_repository.clear_action_files!(issue_id, slug)
        groups.each_with_index do |(action_type, entries), idx|
          name = format('%03d', idx + 1) + '-' + action_type + '.yaml'
          payload = build_payload(action_type, issue_id, entries, source_contents)
          issue_repository.write_change_object(issue_id, slug, name, payload)
          result.files_created += 1
        end
        result.issues_affected += 1
        result.details << "OB #{issue_id}/#{slug}: split into #{groups.length} per-type files"
      end

      def load(issue_id, slug, name)
        issue_repository.read_change_object(issue_id, slug, name)
      end

      def detect_action_type(entry)
        return nil unless entry.is_a?(Hash)

        entry.each_value do |v|
          next unless v.is_a?(String)
          a = Catalogs::ActionTypes.find_last_in(v)
          return a if a
        end
        nil
      end

      def clean_entry(entry, action_type)
        return entry unless entry.is_a?(Hash)

        entry.transform_values do |v|
          next v unless v.is_a?(String)

          v.sub(/\s+#{action_type}\s*\*?\z/i, '').strip
        end
      end

      def build_payload(action_type, issue_id, entries, source_contents = nil)
        data = { 'entries' => entries }
        data['source_contents'] = source_contents if source_contents
        {
          'type' => action_type,
          'date_requested' => nil,
          'date_active' => nil,
          'ob_issue_no' => issue_id.to_s,
          'reference' => "OB-#{issue_id}",
          'identifier' => { 'code' => "#{issue_id}-001" },
          'data' => data,
        }
      end
    end
  end
end
