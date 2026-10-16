# frozen_string_literal: true

require 'set'

module Ituob
  module Normalizers
    # Rename action files whose filename does not match the canonical
    # +NNN-ACTION.yaml+ form.
    #
    # Malformed filenames usually come from the parser extracting a
    # malformed action_type string (e.g. +"by:"+, +"te)"+, +"***"+).
    # This normalizer looks at the file's YAML +type+ field (defaulting
    # to ADD if also malformed) and assigns a canonical name.
    class FilenameCanonicalizer < Base
      CANONICAL_PATTERN = /\A\d{3}-(?:#{Catalogs::ActionTypes.all.join('|')})\.yaml\z/.freeze

      def apply_to(issue_id)
        result = Result.new(name: name)
        issue_repository.each_dataset_slug(issue_id) do |slug|
          next if slug == 'general'
          next if Catalogs::MessageTypes.textual?(slug)

          canonicalize_dir(issue_id, slug, result)
        end
        result
      end

      private

      def canonicalize_dir(issue_id, slug, result)
        renames = []
        max_seq_per_type = Hash.new(0)
        change_object_repository.each_action_file(issue_id, slug) do |seq, action_type, name|
          max_seq_per_type[action_type] = [max_seq_per_type[action_type], seq].max
          next if CANONICAL_PATTERN.match?(name)
        end

        # First pass: find every non-canonical file.
        to_rename = []
        issue_repository.each_change_object_file(issue_id, slug) do |name, _path|
          next if name == 'text.yaml'
          next if name == 'placeholder.yaml'
          next if CANONICAL_PATTERN.match?(name)

          to_rename << name
        end
        return if to_rename.empty?

        used_names = Set.new
        issue_repository.each_change_object_file(issue_id, slug) do |name, _path|
          used_names << name if CANONICAL_PATTERN.match?(name)
        end

        to_rename.each do |old_name|
          data = issue_repository.read_change_object(issue_id, slug, old_name)
          action_type = derive_action_type(old_name, data)
          seq = derive_sequence(old_name)
          new_name = format('%03d', seq) + '-' + action_type + '.yaml'
          while used_names.include?(new_name)
            max_seq_per_type[action_type] += 1
            new_name = format('%03d', max_seq_per_type[action_type]) + '-' + action_type + '.yaml'
          end
          used_names << new_name
          renames << [old_name, new_name]
        end

        # Two-phase rename to avoid collisions.
        renames.each do |old_name, _new|
          from = absolute(issue_id, slug, old_name)
          to = absolute(issue_id, slug, ".#{old_name}.tmp")
          File.rename(from, to)
        end
        renames.each do |old_name, new_name|
          from = absolute(issue_id, slug, ".#{old_name}.tmp")
          to = absolute(issue_id, slug, new_name)
          File.rename(from, to)
          result.files_modified += 1
        end
        result.issues_affected += 1
        result.details << "OB #{issue_id}/#{slug}: renamed #{renames.length} file(s)"
      end

      def derive_action_type(name, data)
        type_str = data.is_a?(Hash) ? data['type'] : nil
        Catalogs::ActionTypes.normalize(type_str) ||
          Catalogs::ActionTypes.normalize(name.split('-', 2).last.to_s.sub(/\.yaml\z/, '')) ||
          'ADD'
      end

      def derive_sequence(name)
        m = name.match(/\A(\d{3})-/)
        m ? m[1].to_i : 1
      end

      def absolute(issue_id, slug, name)
        File.join(issue_repository.output_root, issue_id.to_s, slug.to_s, name)
      end
    end
  end
end
