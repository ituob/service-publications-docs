# frozen_string_literal: true

require 'yaml'

module Ituob
  module Projections
    # Builds the typed Models::RegisterLocale for a register from the
    # metadata.yaml of its seed dataset: the per-language title and the
    # localized terms (column headers) a template reads as
    # `metadata.title[lang]` and `metadata.locale`.
    class RegisterLocale
      # Raised for a register that has no seed dataset metadata to read.
      class MissingMetadataError < ArgumentError; end

      def initialize(register:)
        @register = register
      end

      # Some metadata.yaml files spell Chinese `ch` where the model says `zh`
      # (datasets/1109-Q.708B). Renamed here; the data file is left as is.
      LANGUAGE_ALIASES = { 'ch' => 'zh' }.freeze

      def to_model
        text = File.read(metadata_path)
        data = YAML.safe_load(text)
        # Not a mapping (empty or scalar file): keep the model's own parse error.
        return Models::RegisterLocale.from_yaml(text) unless data.is_a?(Hash)

        Models::RegisterLocale.from_hash(canonical(data))
      end

      private

      def canonical(data)
        data['title'] = canonical_languages(data['title'])
        data['locale'] = data['locale'].map { |term| canonical_languages(term) } if data['locale'].is_a?(Array)
        data['locale'] ||= []
        data
      end

      def canonical_languages(hash)
        return hash unless hash.is_a?(Hash)

        hash.to_h { |lang, text| [LANGUAGE_ALIASES.fetch(lang, lang), text] }
      end

      def metadata_path
        seed_path = @register.seed_path
        raise MissingMetadataError, "Register #{@register.register_id} has no seed dataset" unless seed_path

        path = DataRoot.join(seed_path, 'metadata.yaml')
        return path if File.file?(path)

        raise MissingMetadataError, "Register #{@register.register_id} has no metadata at #{path}"
      end
    end
  end
end
