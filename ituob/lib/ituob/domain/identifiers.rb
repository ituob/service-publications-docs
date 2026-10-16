# frozen_string_literal: true

module Ituob
  module Domain
    # Semantic identifier value objects.
    #
    # Wrapping raw strings and integers in typed values:
    # * Makes function signatures self-documenting.
    # * Centralizes validation (an invalid IssueId raises immediately).
    # * Prevents confusion between publication IDs and dataset slugs.
    module Identifiers
      # An OB Issue number (integer in range 669..current).
      class IssueId
        include Comparable

        attr_reader :value

        def initialize(value)
          case value
          when Integer then @value = value
          when String then @value = Integer(value, 10)
          when IssueId then @value = value.value
          else
            raise TypeError, "IssueId requires Integer or numeric String, got #{value.class}"
          end
          raise ArgumentError, "IssueId out of range: #{@value}" if @value < 1
        end

        def to_s = value.to_s
        def to_i = value
        def to_yaml_node = value.to_s

        def <=>(other)
          return nil unless other.is_a?(IssueId)

          value <=> other.value
        end

        def hash = value.hash
        def eql?(other) = other.is_a?(IssueId) && value == other.value
      end

      # A filesystem-safe dataset slug (e.g. +e118-iin+).
      class DatasetSlug
        include Comparable

        attr_reader :value

        def initialize(value)
          raise TypeError, "DatasetSlug requires String" unless value.is_a?(String)

          @value = value.to_s
          raise ArgumentError, "DatasetSlug empty" if @value.empty?
          raise ArgumentError, "DatasetSlug contains path separators: #{@value}" if @value.include?('/')
        end

        def to_s = value
        def <=>(other) = value <=> other.value
        def hash = value.hash
        def eql?(other) = other.is_a?(self.class) && value == other.value
      end

      # A publication ID (e.g. +E118_IIN+, +NNP+, +R_SP_LM.V+).
      class PublicationId
        include Comparable

        attr_reader :value

        def initialize(value)
          raise TypeError, "PublicationId requires String" unless value.is_a?(String)

          @value = value.to_s
          raise ArgumentError, "PublicationId empty" if @value.empty?
        end

        def to_s = value
        def <=>(other) = value <=> other.value
        def hash = value.hash
        def eql?(other) = other.is_a?(self.class) && value == other.value

        # Resolve this ID to its DatasetSlug via the catalog.
        def slug
          @slug ||= DatasetSlug.new(Catalogs::Publications.slug_for(value))
        end

        # Resolve this ID to its classification via the catalog.
        def classification
          @classification ||= Catalogs::Publications.classify(value)
        end

        def textual? = classification&.textual?
        def structured? = classification&.structured?
      end

      # A reference code identifying a record in a dataset.
      # E.g. +89 41 00+ (E.118 IIN), +AFGC00+ (M.1400 carrier code).
      class RecordCode
        attr_reader :value

        def initialize(value)
          @value = value.to_s
        end

        def to_s = value
        def hash = value.hash
        def eql?(other) = other.is_a?(self.class) && value == other.value
      end
    end
  end
end
