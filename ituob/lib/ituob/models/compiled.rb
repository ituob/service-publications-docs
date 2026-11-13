# frozen_string_literal: true

require 'lutaml/lml'

module Ituob
  module Models
    # Data-shape classes compiled at load time from the LML ontology
    # (ituob/ontology/messages.lml). The ontology is the single source
    # for their attributes, types, cardinality and defaults; anything
    # beyond data shape stays in Ruby.
    #
    # CONSTRAINTS:
    # - a compiled class's class-typed attributes resolve to the
    #   compiler's anonymous classes, so every class-referenced
    #   attribute type of a CLASS_NAMES member must itself be in
    #   CLASS_NAMES — otherwise the hand-written class of that type no
    #   longer matches at serialization time and lutaml-model 0.8 raises
    #   IncorrectModelError (verify_parser_equivalence catches it).
    # - Hash-typed attributes (LML has no Hash primitive) are typed
    #   :hash at declaration time via Compiler#resolve_type.
    # - A hand subclass of a compiled base (DPEntry < NumberingPlanEntry)
    #   keeps its class in Ruby when the inheritance is semantic
    #   (specs assert the hierarchy); its sibling Action is then also
    #   hand-written, since a compiled Action's entries would type to
    #   the anonymous Entry instead of the hand one (DPAction).
    #
    # The compiled classes are registered under Ituob::Models with the
    # same names the hand-written classes had, so every reference —
    # including ListVIIIAction's `entries` attribute type — resolves
    # transparently.
    #
    # Extend CLASS_NAMES to migrate further families; the drift-guard
    # spec (ontology_spec.rb) keeps the ontology and any remaining
    # hand-written classes in lockstep.
    module Compiled
      ONTOLOGY_PATH = File.expand_path('../../ituob/ontology/messages.lml', __dir__)

      CLASS_NAMES = %w[
        E164ACNEntry
        E164BEntry
        E164CCAction
        E164CCEntry
        E164DEntry
        E164DNoteNEntry
        E164DNoteOEntry
        E212MNCAction
        E212MNCEntry
        E218TRCCAction
        E218TRCCEntry
        F32TDIAction
        F32TDIEntry
        F400Action
        F400Entry
        GeneralApprovedRecommendation
        GeneralMid
        GeneralSanc
        GeneralServiceRestriction
        GeneralTelephoneCommunication
        GeneralTelephoneSection
        GeneralTelephoneService
        Identifier
        IptnEntry
        IssueAuthor
        IssueContact
        IssueMetadata
        KeyHistoryEntry
        ListVIIIAction
        ListVIIICentralizingOffice
        ListVIIIMeasurement
        ListVIIIStation
        M1400Action
        M1400Entry
        MultilingualString
        NNPAction
        NumberingPlanEntry
        ProjectionProvenance
        Q708ISPCAction
        Q708ISPCEntry
        Q708SANCAction
        Q708SANCEntry
        RR251Action
        RR251Entry
        RegisterEdition
        RegisterKeyHistory
        T35AssignmentAuthority
        T35NAAction
        T35NAEntry
        TextAction
        X121DNICAction
        X121DNICEntry
      ].freeze

      # The single compiler instance for the ontology — memoized so the
      # drift-guard spec and any tooling observe the same anonymous
      # classes that were registered under Ituob::Models.
      def self.compiler
        @compiler ||= begin
          c = Compiler.new
          c.compile(File.open(ONTOLOGY_PATH))
          c
        end
      end

      # ModelCompiler lacks a Hash primitive (falls back to String and
      # YAML-stringifies the value); map it at declaration time so the
      # cast rules are built correctly from the start.
      #
      # Editor-era issue metadata carries IssueAuthor.name as a scalar
      # string OR a MultilingualString mapping. lutaml-lml 0.2.0 cannot
      # declare unions, so the union is declared here, at declaration
      # time (lutaml-model builds cast rules at declaration; re-typing
      # a compiled attribute afterwards does not take). GRAPH.adoc
      # tracks this as an LML expressiveness gap.
      class Compiler < Lutaml::Lml::ModelCompiler
        UNION_ATTRIBUTES = {
          %w[IssueAuthor name] => ["MultilingualString", :string],
          # Older service-restriction rows key the country by plain name;
          # newer rows carry the multilingual string.
          %w[GeneralServiceRestriction country] => ["MultilingualString", :string],
        }.freeze

        # Ontology names for the lossless corpus value types
        # (see DateOrText, HashOrText).
        LOSSLESS_TYPES = {
          "DateOrText" => "Ituob::Models::DateOrText",
          "HashOrText" => "Ituob::Models::HashOrText",
        }.freeze

        # lutaml-model omits an empty value ("" or []) from the
        # serialized hash unless the mapping says render_empty. These
        # classes hold values the corpus stores empty on purpose
        # (`communications: []`, `incomplete: false`), so every attribute
        # is mapped explicitly and renders what it holds.
        RENDER_EMPTY_CLASSES = %w[GeneralTelephoneSection IssueMetadata].freeze

        def apply_key_value_mappings
          super
          map_edition_items
          RENDER_EMPTY_CLASSES.each do |name|
            klass = compiled_classes.fetch(name)
            names = klass.attributes.keys
            klass.key_value do
              names.each { |attr| map attr.to_s, to: attr, render_empty: true }
            end
          end
        end

        def resolve_type(type_name)
          return :hash if type_name == "Hash"
          return Object.const_get(LOSSLESS_TYPES.fetch(type_name)) if LOSSLESS_TYPES.key?(type_name)

          super
        end

        # lutaml-lml 0.3.1 builds every class directly on Serializable and
        # LML has no inheritance syntax. Entry classes must descend from
        # the hand-written Entry anchor so a heterogeneous collection
        # (RegisterEdition#items) can hold concrete instances of any of
        # them; this mirrors ModelCompiler#build_compiled_class otherwise.
        def build_compiled_class(def_obj)
          return super unless entry_class?(def_obj)

          all_attrs = build_attributes(def_obj)
          immediate, deferred = all_attrs.partition do |(_, raw_type, type, _)|
            type != :string || TYPE_MAP.key?(raw_type) || raw_type.start_with?('reference:(')
          end
          compiled_klass = Class.new(Ituob::Models::Entry) do
            immediate.each { |attr_name, _raw, type, options| attribute attr_name, type, **options }
          end
          @forward_refs[def_obj.name.to_s] = deferred unless deferred.empty?
          compiled_klass
        end

        def build_attributes(klass_def)
          super.map do |attr_name, raw_type, type, options|
            options = projection_options(klass_def, options)
            if klass_def.name.to_s == 'RegisterEdition' && attr_name == :items
              next [attr_name, raw_type, Ituob::Models::Entry, options.merge(polymorphic: true)]
            end
            members = UNION_ATTRIBUTES[[klass_def.name.to_s, attr_name.to_s]]
            next [attr_name, raw_type, type, options] unless members

            resolved = members.map do |m|
              m.is_a?(String) ? compiled_classes.fetch(m) : m
            end
            [attr_name, raw_type, Lutaml::Model::Type::Union,
             options.merge(union_member_types: resolved)]
          end
        end

        # Register row classes carry the `_class` discriminator
        # (KeyHistoryEntry, a plain value class, does not).
        def entry_class?(klass_def)
          name = klass_def.name.to_s
          name.end_with?('Entry') && CLASS_NAMES.include?(name) &&
            Array(klass_def.attributes).any? { |attr| attr.name.to_s == '_class' }
        end

        # The discriminator is the entry's own `_class`; hydration sets it
        # so each item serializes with, and restores, its concrete class.
        def map_edition_items
          edition = compiled_classes.fetch('RegisterEdition')
          # Compiled entries are not constants yet while compiling.
          names = (CLASS_NAMES + Ituob::Models.constants.map(&:to_s)).grep(/Entry\z/).uniq
          class_map = names.to_h { |name| [name, "Ituob::Models::#{name}"] }
          attrs = edition.attributes.keys
          edition.key_value do
            attrs.each do |attr|
              if attr == :items
                map 'items', to: :items,
                             polymorphic: { attribute: '_class', class_map: class_map }
              else
                map attr.to_s, to: attr
              end
            end
          end
        end

        # Deserialization assigns missing fields after initialize;
        # projection collections need attribute defaults as well.
        def projection_options(klass_def, options)
          return options unless %w[RegisterEdition RegisterKeyHistory].include?(klass_def.name.to_s) && options[:collection]

          options.merge(default: -> { [] })
        end
      end

      def self.load!
        CLASS_NAMES.each do |name|
          klass = compiler.compiled_classes.fetch(name)
          ensure_collections_default_to_empty(klass)
          preserve_empty_strings(name, klass)
          Models.const_set(name, klass)
        end

        nil
      end

      # These registers distinguish a printed blank from a missing field.
      # Explicit mappings retain that distinction when Entry objects are
      # serialized, while still omitting absent/nil values.
      def self.preserve_empty_strings(name, klass)
        return unless %w[F400Entry NumberingPlanEntry].include?(name)

        attributes = klass.attributes
        klass.key_value do
          attributes.each do |attribute, definition|
            map attribute.to_s, to: attribute,
                                render_empty: definition.type == Lutaml::Model::Type::String
          end
        end
      end

      # Hand-written model classes initialize collection attributes to
      # [] (e.g. the old ListVIIIStation guarded @measurements); parsers
      # rely on being able to `<<` immediately. The compiled classes get
      # the same contract via a prepended initializer.
      def self.ensure_collections_default_to_empty(klass)
        guard = Module.new do
          define_method(:initialize) do |*args, **kwargs, &block|
            super(*args, **kwargs, &block)
            self.class.attributes.each do |name, attr|
              next unless attr.collection?

              public_send("#{name}=", []) if public_send(name).nil?
            end
          end
        end
        klass.prepend(guard)
      end
    end
  end
end
