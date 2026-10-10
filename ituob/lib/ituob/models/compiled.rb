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
        GeneralSanc
        GeneralTelephoneService
        IptnEntry
        IssueAuthor
        IssueContact
        IssueMetadata
        ListVIIIAction
        ListVIIICentralizingOffice
        ListVIIIMeasurement
        ListVIIIStation
        M1400Action
        M1400Entry
        MultilingualString
        NNPAction
        NumberingPlanEntry
        Q708ISPCAction
        Q708ISPCEntry
        Q708SANCAction
        Q708SANCEntry
        RR251Action
        RR251Entry
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
        }.freeze

        def resolve_type(type_name)
          return :hash if type_name == "Hash"

          super
        end

        def build_attributes(klass_def)
          super.map do |attr_name, raw_type, type, options|
            members = UNION_ATTRIBUTES[[klass_def.name.to_s, attr_name.to_s]]
            next [attr_name, raw_type, type, options] unless members

            resolved = members.map do |m|
              m.is_a?(String) ? compiled_classes.fetch(m) : m
            end
            [attr_name, raw_type, Lutaml::Model::Type::Union,
             options.merge(union_member_types: resolved)]
          end
        end
      end

      def self.load!
        CLASS_NAMES.each do |name|
          klass = compiler.compiled_classes.fetch(name)
          ensure_collections_default_to_empty(klass)
          Models.const_set(name, klass)
        end

        nil
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
