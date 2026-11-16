# frozen_string_literal: true

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

      def to_model
        Models::RegisterLocale.from_yaml(File.read(metadata_path))
      end

      private

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
