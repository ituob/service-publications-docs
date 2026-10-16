# frozen_string_literal: true

module Ituob
  module Repositories
    # Read and write dataset-level data (metadata, schema, current snapshot).
    class DatasetRepository
      attr_reader :root

      def initialize(root:)
        @root = root.to_s
        @store = YamlStore.new(root: root)
      end

      # Enumerate every dataset slug (subdirectory) under +root+.
      def each_slug
        return enum_for(:each_slug) unless block_given?

        return unless Dir.exist?(@root)

        Dir.children(@root).sort.each do |name|
          next if name.start_with?('.')
          next if name.end_with?('.yaml') # schema-metadata.yaml etc.

          path = File.join(@root, name)
          yield name if File.directory?(path)
        end
      end

      def read_metadata(slug) = @store.read("#{slug}/metadata.yaml")
      def read_schema(slug) = @store.read("#{slug}/schema-data.yaml")
      def read_data(slug) = @store.read("#{slug}/data.yaml")

      def entry_count(slug)
        data = read_data(slug)
        return 0 unless data
        return data.length if data.is_a?(Array)
        return data['data'].length if data.is_a?(Hash) && data['data'].is_a?(Array)
        return data['data'].keys.length if data.is_a?(Hash) && data['data'].is_a?(Hash)

        0
      end
    end
  end
end
