# frozen_string_literal: true

module Ituob
  module Verifiers
    # Verify that a dataset's +data.yaml+ matches its Word source snapshot.
    #
    # This is a lighter-weight version of +SourceDocVerifier+ that checks
    # a single dataset rather than all of them.
    class DatasetSnapshotVerifier < Base
      attr_reader :dataset_repository, :refs_root

      def initialize(dataset_repository:, refs_root:)
        super()
        @dataset_repository = dataset_repository
        @refs_root = refs_root
      end

      def verify
        result = Result.new(name: name)
        @dataset_repository.each_slug do |slug|
          result.stats[:slug] ||= 0
          result.stats[:slug] += 1
          data = @dataset_repository.read_data(slug)
          next unless data

          doc_path = locate_doc(slug)
          unless doc_path
            result.warnings << "#{slug}: no source doc"
            next
          end

          hits = sample_hits(data, doc_path)
          result.details << { slug: slug, hits: hits[:hits], total: hits[:total] }
          result.errors << "#{slug}: 0/#{hits[:total]} sample hits" if hits[:hits].zero? && hits[:total].positive?
        end
        result
      end

      private

      def locate_doc(slug)
        ref_dir = File.join(@refs_root, slug)
        return nil unless Dir.exist?(ref_dir)

        candidates = Dir.children(ref_dir).select { |n| n =~ /-MSW-E\.docx?\z/i }
        candidates.first && File.join(ref_dir, candidates.first)
      end

      def sample_hits(data, doc_path)
        sample = take_sample(data)
        return { hits: 0, total: 0 } if sample.empty?

        doc = SourceDocuments::DocxReader.read(doc_path)
        total = sample.length
        hits = sample.count do |entry|
          candidate_strings(entry).any? { |needle| doc.haystack.include?(needle) }
        end
        { hits: hits, total: total }
      end

      def take_sample(data)
        return [] unless data

        case data
        when Array then data.first(5) + data.last(5)
        when Hash
          if data['data'].is_a?(Array)
            take_sample(data['data'])
          else
            data.values.first(5) + data.values.last(5)
          end
        else []
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
