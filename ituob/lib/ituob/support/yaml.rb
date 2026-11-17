# frozen_string_literal: true

require 'yaml'

module Ituob
  module Support
    # Stateless utility for reading OB-style YAML safely.
    #
    # All OB YAML files (catalogs, schemas fragments, change files,
    # seed data) use the same feature set: aliases permitted, plus
    # Date/Time/DateTime/Symbol deserialization. Centralizing the
    # call here means a single source of truth for the policy.
    #
    # Files are always read as UTF-8.
    module Yaml
      DEFAULT_PERMITTED_CLASSES = [Date, Time, DateTime, Symbol].freeze
      YAML_1_1_BOOLEAN = /\A(?:yes|true|on|no|false|off)\z/i
      private_constant :YAML_1_1_BOOLEAN

      module_function

      # Read +path+ as UTF-8 and parse it as YAML. Returns nil for
      # empty files (mirrors +YAML.safe_load+ behaviour).
      def safe_load_file(path)
        safe_load_string(File.read(path, encoding: 'utf-8'))
      end

      # Read an OB source file (issues/*/amendments.yaml, general.yaml).
      # ProseMirror text nodes carry printed text, so a bare YES, NO, ON
      # or OFF must stay the string that was printed rather than become
      # the YAML 1.1 boolean Psych resolves it to. Aliases are not
      # permitted, as in +YAML.load_file+.
      def load_source_file(path)
        document = Psych.parse_file(path)
        return false unless document

        preserve_printed_text(document)
        class_loader = Psych::ClassLoader::Restricted.new(%w[Date Time], [])
        scanner = Psych::ScalarScanner.new(class_loader)
        Psych::Visitors::NoAliasRuby.new(scanner, class_loader).accept(document)
      end

      # Parse a YAML string with the project's standard policy.
      def safe_load_string(contents)
        YAML.safe_load(contents,
                       aliases: true,
                       permitted_classes: DEFAULT_PERMITTED_CLASSES)
      end

      def preserve_printed_text(node)
        node.children&.each { |child| preserve_printed_text(child) }
        text = boolean_text_scalar(node) if node.is_a?(Psych::Nodes::Mapping)
        quote(text) if text
      end
      private_class_method :preserve_printed_text

      def boolean_text_scalar(mapping)
        fields = scalar_keyed_fields(mapping)
        text = fields['text']
        return unless fields['type'].is_a?(Psych::Nodes::Scalar) && fields['type'].value == 'text'

        text if text.is_a?(Psych::Nodes::Scalar) && text.plain && boolean?(text.value)
      end
      private_class_method :boolean_text_scalar

      def scalar_keyed_fields(mapping)
        mapping.children.each_slice(2)
               .select { |key, _| key.is_a?(Psych::Nodes::Scalar) }
               .to_h { |key, value| [key.value, value] }
      end
      private_class_method :scalar_keyed_fields

      def quote(scalar)
        scalar.plain = false
        scalar.quoted = true
        scalar.style = Psych::Nodes::Scalar::DOUBLE_QUOTED
      end
      private_class_method :quote

      def boolean?(value)
        YAML_1_1_BOOLEAN.match?(value)
      end
      private_class_method :boolean?
    end
  end
end
