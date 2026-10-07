# frozen_string_literal: true

module Ituob
  module Verifiers
    # Verify that a dataset's +data.yaml+ matches its authoritative Word
    # snapshot in +service-publications-refs+.
    class SourceDocVerifier < Base
      attr_reader :refs_root

      def initialize(issue_repository:, refs_root:)
        super(issue_repository: issue_repository)
        @refs_root = refs_root
      end

      def verify
        result = Result.new(name: name)
        result.stats[:datasets_verified] = 0
        result.stats[:datasets_ok] = 0
        result.stats[:datasets_missing_source] = 0

        Catalogs::Publications.each_entry do |entry|
          next if entry.textual?

          doc_path = find_source_doc(entry.slug)
          if doc_path.nil?
            result.stats[:datasets_missing_source] += 1
            next
          end

          result.stats[:datasets_verified] += 1
          data_yaml_path = find_data_yaml(entry.slug)
          if data_yaml_path.nil?
            result.errors << "#{entry.slug}: missing data.yaml"
            next
          end

          if sample_matches?(data_yaml_path, doc_path)
            result.stats[:datasets_ok] += 1
          else
            result.errors << "#{entry.slug}: data.yaml does not match source #{File.basename(doc_path)}"
          end
        end
        result
      end

      private

      def find_source_doc(slug)
        # Try service-publications-refs/<DatasetSlug>/*-MSW-E.doc[x]
        # Or fall back to lookup by old publication-ref name.
        ref_dir = File.join(@refs_root, slug)
        return nil unless Dir.exist?(ref_dir)

        candidates = Dir.children(ref_dir).select do |n|
          n =~ /-MSW-E\.docx?\z/i
        end
        return File.join(ref_dir, candidates.first) if candidates.any?

        nil
      end

      def find_data_yaml(slug)
        path = File.join(issue_repository.output_root, '..', 'datasets', slug, 'data.yaml')
        return nil unless File.file?(path)

        path
      end

      def sample_matches?(data_yaml_path, doc_path)
        data = Ituob::Support::Yaml.safe_load_file(data_yaml_path)
        document = read_source_doc(doc_path)

        sample = sample_of(data)
        sample.any? do |entry|
          candidate_strings(entry).any? { |needle| document.haystack.include?(needle) }
        end
      end

      def read_source_doc(path)
        case File.extname(path).downcase
        when '.docx' then SourceDocuments::DocxReader.read(path)
        when '.doc'  then SourceDocuments::DocReader.read(path)
        else
          SourceDocuments::Document.new(source_path: path, paragraphs: [], tables: [])
        end
      end

      def sample_of(data)
        return [] unless data

        if data.is_a?(Array)
          data.first(5) + data.last(5)
        elsif data.is_a?(Hash) && data['data'].is_a?(Array)
          sample_of(data['data'])
        elsif data.is_a?(Hash)
          data.values.first(5) + data.values.last(5)
        else
          []
        end
      end

      def candidate_strings(entry)
        return [] unless entry.is_a?(Hash)

        out = []
        entry.each_value do |v|
          case v
          when String then out << v
          when Hash then v.each_value { |vv| out << vv if vv.is_a?(String) }
          when Array then v.each { |vv| out << vv if vv.is_a?(String) }
          end
        end
        out.reject { |s| s.strip.empty? || s.strip.length < 3 }
      end
    end
  end
end
