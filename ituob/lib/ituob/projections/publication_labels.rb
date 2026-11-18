# frozen_string_literal: true

module Ituob
  module Projections
    # Publication labels absent from, or mistranslated in, the legacy metadata.
    # Keep the overrides here so published corpus snapshots remain immutable.
    module PublicationLabels
      def self.for_dataset(dataset, metadata)
        labels = overrides.fetch(dataset, [])
        return metadata if labels.empty?

        data = metadata.to_hash
        locale = Array(data['locale']).to_h { |label| [label.fetch('key'), label] }
        labels.each { |label| locale[label.fetch('key')] = label }
        metadata.class.from_hash(data.merge('locale' => locale.values))
      end

      def self.overrides
        @overrides ||= %w[publication_labels rr251_labels t35b_labels static_header_labels].each_with_object({}) do |name, labels|
          Support::Yaml.safe_load_file(File.expand_path("#{name}.yaml", __dir__)).each do |dataset, terms|
            labels[dataset] = Array(labels[dataset]) + terms
          end
        end
      end
      private_class_method :overrides
    end
  end
end
