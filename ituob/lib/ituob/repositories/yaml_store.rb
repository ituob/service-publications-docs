# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Ituob
  module Repositories
    # Low-level YAML read/write helper.
    #
    # All YAML I/O in the codebase goes through this class so we have one
    # place to handle permitted classes, aliases, encoding, and the
    # "strip leading document separator" convention used in this project.
    class YamlStore
      def initialize(root:)
        @root = root.to_s
      end

      # Read and parse a YAML file relative to +root+.
      # Returns +nil+ if the file does not exist.
      def read(relative_path)
        path = absolute(relative_path)
        return nil unless File.file?(path)

        Ituob::Support::Yaml.safe_load_file(path)
      end

      # Serialize +data+ and write to +relative_path+, creating parent
      # directories as needed. The leading +---\n+ document separator is
      # stripped to match project convention.
      def write(relative_path, data)
        path = absolute(relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        payload = YAML.dump(data)
        payload = payload.sub(/\A---\n/, '')
        File.write(path, payload, encoding: 'utf-8')
      end

      # +true+ if a file exists at +relative_path+.
      def exists?(relative_path)
        File.file?(absolute(relative_path))
      end

      # Return an absolute path string for +relative_path+ under +root+.
      def absolute(relative_path)
        File.join(@root, relative_path.to_s)
      end

      # Yield every immediate subdirectory under +root+ whose name matches
      # a regex (default: numeric — matches issue IDs).
      def each_subdirectory(match: /\A\d+\z/)
        return enum_for(:each_subdirectory, match: match) unless block_given?

        return unless Dir.exist?(@root)

        Dir.children(@root).sort.each do |name|
          next unless name =~ match

          path = File.join(@root, name)
          yield name, path if File.directory?(path)
        end
      end
    end
  end
end
