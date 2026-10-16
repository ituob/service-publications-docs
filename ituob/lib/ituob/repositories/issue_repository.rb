# frozen_string_literal: true

module Ituob
  module Repositories
    # Read and write OB Issue data.
    #
    # Two root paths are tracked:
    #
    # * +source_root+ — path to +itu-ob-data/issues+ (the authoritative
    #   source). Provides +read_meta+, +read_general+, +read_amendments+,
    #   +read_annexes+.
    # * +output_root+ — path to +ob-issues+ (the normalized output).
    #   Provides +each_issue_id+, +read_change_object+, +write_change_object+,
    #   +delete_change_object+.
    class IssueRepository
      attr_reader :source_root, :output_root

      def initialize(source_root:, output_root:)
        @source_root = source_root.to_s
        @output_root = output_root.to_s
        @source_store = YamlStore.new(root: source_root)
        @output_store = YamlStore.new(root: output_root)
      end

      # ---- Source side ----

      # Enumerate every IssueId in the source tree, ascending.
      def each_source_issue_id
        return enum_for(:each_source_issue_id) unless block_given?

        @source_store.each_subdirectory.each do |name, _path|
          yield Domain::Identifiers::IssueId.new(name)
        end
      end

      def read_meta(issue_id)
        @source_store.read("#{issue_id}/meta.yaml")
      end

      def read_general(issue_id)
        @source_store.read("#{issue_id}/general.yaml")
      end

      def read_amendments(issue_id)
        @source_store.read("#{issue_id}/amendments.yaml")
      end

      def read_annexes(issue_id)
        @source_store.read("#{issue_id}/annexes.yaml")
      end

      # ---- Output side ----

      def each_output_issue_id
        return enum_for(:each_output_issue_id) unless block_given?

        @output_store.each_subdirectory.each do |name, _path|
          yield Domain::Identifiers::IssueId.new(name)
        end
      end

      # Enumerate every subdirectory (dataset slug) under an output issue.
      def each_dataset_slug(issue_id)
        return enum_for(:each_dataset_slug, issue_id) unless block_given?

        issue_dir = File.join(@output_root, issue_id.to_s)
        return unless Dir.exist?(issue_dir)

        Dir.children(issue_dir).sort.each do |name|
          path = File.join(issue_dir, name)
          yield name if File.directory?(path)
        end
      end

      # Enumerate every .yaml file under an issue × dataset directory.
      def each_change_object_file(issue_id, slug)
        return enum_for(:each_change_object_file, issue_id, slug) unless block_given?

        dir = File.join(@output_root, issue_id.to_s, slug.to_s)
        return unless Dir.exist?(dir)

        Dir.children(dir).sort.each do |name|
          path = File.join(dir, name)
          yield name, path if File.file?(path) && name.end_with?('.yaml')
        end
      end

      def read_change_object(issue_id, slug, filename)
        @output_store.read("#{issue_id}/#{slug}/#{filename}")
      end

      def write_change_object(issue_id, slug, filename, payload)
        @output_store.write("#{issue_id}/#{slug}/#{filename}", payload)
      end

      def delete_change_object(issue_id, slug, filename)
        path = @output_store.absolute("#{issue_id}/#{slug}/#{filename}")
        File.delete(path) if File.file?(path)
      end

      # Copy +meta.yaml+ and +annexes.yaml+ from source to output.
      def copy_meta_and_annexes(issue_id)
        dir = File.join(@output_root, issue_id.to_s)
        FileUtils.mkdir_p(dir)
        %w[meta.yaml annexes.yaml].each do |f|
          src = File.join(@source_root, issue_id.to_s, f)
          dst = File.join(dir, f)
          FileUtils.cp(src, dst) if File.file?(src)
        end
      end

      # Remove and recreate the output directory for an issue (clean rebuild).
      def reset_output_issue(issue_id)
        dir = File.join(@output_root, issue_id.to_s)
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
      end
    end
  end
end
