# frozen_string_literal: true

require 'lutaml/lml'

module Ituob
  module Models
    # Data-shape classes compiled at load time from the LML ontology
    # (ituob/ontology/messages.lml). The ontology is the single source
    # for their attributes, types, cardinality and defaults; anything
    # beyond data shape stays in Ruby.
    #
    # CONSTRAINT: a compiled class's class-typed attributes resolve to
    # the compiler's anonymous classes, so every class-referenced
    # attribute type of a CLASS_NAMES member must itself be in
    # CLASS_NAMES — otherwise the hand-written class of that type no
    # longer matches at serialization time and lutaml-model 0.8 raises
    # IncorrectModelError (verify_parser_equivalence catches it).
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
        GeneralApprovedRecommendation
        IptnEntry
        IssueAuthor
        IssueContact
        IssueMetadata
        ListVIIICentralizingOffice
        ListVIIIMeasurement
        ListVIIIStation
        MultilingualString
        T35AssignmentAuthority
        TextAction
      ].freeze

      # The single compiler instance for the ontology — memoized so the
      # drift-guard spec and any tooling observe the same anonymous
      # classes that were registered under Ituob::Models.
      def self.compiler
        @compiler ||= begin
          c = Lutaml::Lml::ModelCompiler.new
          c.compile(File.open(ONTOLOGY_PATH))
          c
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
