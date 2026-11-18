# frozen_string_literal: true

module Ituob
  module Normalizers
    # NBSP is significant in printed prose, but must not distinguish lookup
    # keys or codes. Apply the same policy to freshly built and stored patches.
    class KeyWhitespace < Base
      CODE_FIELDS = %w[code country_code network_code network_codes office_code
                       iso_code mcc_mnc_codes tmcc_code carrier_code ipsc
                       cc_ic dnic_number issue_id_number code_bit].freeze

      def self.clean_value(value)
        case value
        when String then value.tr("\u00a0", ' ')
        when Hash then value.transform_values { |item| clean_value(item) }
        when Array then value.map { |item| clean_value(item) }
        else value
        end
      end

      def self.clean_data(data, slug)
        return data unless data.is_a?(Hash)

        registers = Catalogs::Registers.all.select { |entry| entry.amendment_slug == slug }
        fields = registers.flat_map { |entry| [entry.key_field, entry.fallback_key_fields] }.flatten.compact
        fields = (fields + CODE_FIELDS).uniq
        cleaned = data.dup
        fields.each { |field| cleaned[field] = clean_value(data[field]) if data.key?(field) }
        if data['entries'].is_a?(Array)
          cleaned['entries'] = data['entries'].map do |row|
            next row unless row.is_a?(Hash)

            row.dup.tap do |entry|
              fields.each { |field| entry[field] = clean_value(row[field]) if row.key?(field) }
            end
          end
        end
        cleaned
      end

      def self.clean_patch(patch, slug)
        patch.dup.tap do |cleaned|
          cleaned['identifier'] = clean_value(patch['identifier']) if patch.key?('identifier')
          cleaned['data'] = clean_data(patch['data'], slug) if patch.key?('data')
        end
      end

      def apply_to(issue_id)
        result = Result.new(name: name)
        issue_repository.each_dataset_slug(issue_id) do |slug|
          change_object_repository.each_action_file(issue_id, slug) do |_seq, _type, name|
            patch = issue_repository.read_change_object(issue_id, slug, name)
            next unless patch.is_a?(Hash)

            cleaned = self.class.clean_patch(patch, slug)
            next if cleaned == patch

            issue_repository.write_change_object(issue_id, slug, name, cleaned)
            result.files_modified += 1
            result.details << "OB #{issue_id}/#{slug}/#{name}: normalized key/code NBSP"
          end
        end
        result.issues_affected = 1 if result.files_modified.positive?
        result
      end
    end
  end
end
