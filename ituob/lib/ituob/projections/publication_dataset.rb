# frozen_string_literal: true

module Ituob
  module Projections
    # Ordered, typed snapshots selected from an explicit publication allowlist.
    class PublicationDataset
      DATASETS = {
        '955-E.180' => 'PublicationE180Entry',
        '1117-E.212A' => 'PublicationE212AEntry',
        '1117-E.212A-MCCMNC' => 'PublicationE212AMccMncEntry',
        '1162-E.212' => 'PublicationE212Entry',
        '1162-E.212-ET' => 'PublicationE212EtEntry',
        '1162-E.212-MCC-Others' => 'PublicationE212OthersEntry',
        '1162-E.212-Shared-MCC' => 'PublicationE212SharedEntry',
        '669-F.1' => 'PublicationF1Entry',
        '978-F.68' => 'PublicationF68Entry',
        '978-F.68-A1' => 'PublicationF68A1Entry',
        '978-F.68-A2' => 'PublicationF68A2Entry',
        '991-PP.RES.21.pp' => 'PublicationPp21Entry',
        '1000-SR.1' => 'PublicationSr1Entry',
        '1154-RR.25.1' => 'PublicationRr251Entry',
        '1002-T.35' => 'PublicationT35Entry',
        '1001-T.35B' => 'PublicationT35BEntry',
        '976-X.121A' => 'PublicationX121AEntry',
      }.freeze

      class InvalidDatasetError < ArgumentError; end

      def initialize(dataset:, as_of:)
        @dataset = dataset.to_s
        @model_name = DATASETS[@dataset]
        unless @model_name
          raise InvalidDatasetError, "Unknown publication dataset #{dataset.inspect}; known: #{DATASETS.keys.join(', ')}"
        end

        @issue = Integer(as_of.to_s, 10, exception: false)
        unless @issue == @dataset.split('-').first.to_i
          raise Provider::UnknownIssueError, "Dataset #{@dataset} publication is only available at issue #{@dataset.split('-').first}"
        end
      end

      def to_model
        rows = read('data.yaml')
        unless rows.is_a?(Array) && !rows.empty? && rows.all? { |row| row.is_a?(Hash) && !row.empty? }
          raise InvalidDatasetError, "Dataset #{@dataset} publication data must contain nonempty rows"
        end

        type = Models.const_get(@model_name)
        items = rows.each_with_index.map do |row, index|
          item = type.from_hash(row.merge('_class' => @model_name))
          preserve!(row, item.to_hash, "row #{index + 1}")
          item
        end
        result = Models::PublicationDataset.new(
          dataset: @dataset, as_of_issue: @issue, items: items, metadata: metadata
        )
        if @dataset == '1154-RR.25.1'
          countries = read('countries.yaml')
          result.countries = countries.map do |country|
            key = country.fetch('key')
            unless key.is_a?(String) && key.match?(/\A[a-z0-9_-]+\z/)
              raise InvalidDatasetError, "Dataset #{@dataset} has invalid country key #{key.inspect}"
            end
            data = read("data/#{key}.yaml")
            item = Models::PublicationCountry.from_hash(country)
            item.data = Models::PublicationRr251CountryData.from_hash(data)
            preserve!(data, item.data.to_hash, "countries.#{key}.data")
            item
          end
          preserve!(countries, result.countries.map(&:to_hash), 'countries')
        elsif @dataset == '1001-T.35B'
          acronyms = read('acronyms.yaml').transform_keys(&:to_s)
          result.acronyms = Models::PublicationAcronyms.from_hash(acronyms)
          preserve!(acronyms, result.acronyms.to_hash, 'acronyms')
        end
        result
      end

      private

      def read(filename)
        path = DataRoot.join('datasets', @dataset, filename)
        unless File.file?(path)
          raise InvalidDatasetError, "Dataset #{@dataset} publication is missing #{filename}"
        end

        duplicates = Support::Yaml.duplicate_mapping_keys(path)
        unless duplicates.empty?
          raise InvalidDatasetError, "Dataset #{@dataset} #{filename} has duplicate fields: #{duplicates.join(', ')}"
        end

        Support::Yaml.safe_load_file(path)
      end

      def metadata
        data = read('metadata.yaml')
        unless data.is_a?(Hash) && (data['title'].is_a?(Hash) && !data['title'].empty? || data['locale'].is_a?(Array) && !data['locale'].empty?)
          raise InvalidDatasetError, "Dataset #{@dataset} has invalid publication metadata"
        end

        data['title'] = canonical_languages(data['title']) if data.key?('title')
        if data.key?('locale')
          unless data['locale'].is_a?(Array) && data['locale'].all? { |label| label.is_a?(Hash) && label['key'].is_a?(String) && !label['key'].empty? }
            raise InvalidDatasetError, "Dataset #{@dataset} has invalid publication metadata locale"
          end
          data['locale'] = data['locale'].map { |label| canonical_languages(label) }
        end
        model = Models::PublicationMetadata.from_hash(data)
        preserve!(data, model.to_hash, 'metadata')
        PublicationLabels.for_dataset(@dataset, model)
      end

      def canonical_languages(labels)
        return labels unless labels.is_a?(Hash)

        labels.each_with_object({}) do |(key, value), canonical|
          name = RegisterLocale::LANGUAGE_ALIASES.fetch(key, key)
          if canonical.key?(name) && canonical[name] != value
            raise InvalidDatasetError, "Dataset #{@dataset} metadata has conflicting #{name} language aliases"
          end
          canonical[name] = value
        end
      end

      # Compare every source leaf, including empty strings, false and numeric
      # scalar types. Extra model defaults do not replace any source value.
      def preserve!(source, projected, path)
        case source
        when Hash
          source.each do |key, value|
            unless projected.is_a?(Hash) && projected.key?(key)
              raise InvalidDatasetError, "Dataset #{@dataset} publication loses #{path}.#{key}"
            end
            preserve!(value, projected[key], "#{path}.#{key}")
          end
        when Array
          unless projected.is_a?(Array) && source.size == projected.size
            raise InvalidDatasetError, "Dataset #{@dataset} publication loses #{path}"
          end
          source.zip(projected).each_with_index { |(left, right), index| preserve!(left, right, "#{path}[#{index}]") }
        else
          unless source == projected && source.class == projected.class
            raise InvalidDatasetError, "Dataset #{@dataset} publication changes #{path}: #{source.inspect} to #{projected.inspect}"
          end
        end
      end
    end
  end
end
