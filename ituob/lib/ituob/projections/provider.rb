# frozen_string_literal: true

module Ituob
  # Data provider for metanorma-plugin-lutaml `lutaml_data` blocks.
  #
  #   provider = Ituob::Provider.new
  #   provider.edition(register: 'e212-mnc', as_of: 1170)
  #   provider.history(register: 'e212-mnc', key: '234 | 15', as_of: 1170)
  #
  # +register+ is the catalog slug (`e212-mnc`) or register id
  # (`E212_MNC`); +as_of+ is an OB issue number. Both queries return
  # lutaml-model objects (Models::RegisterEdition, Models::RegisterKeyHistory)
  # carrying ProjectionProvenance, so they reach Liquid through to_liquid.
  #
  # == Data root
  #
  # The projections read catalogs/, datasets/ and ob-issues/ from a data
  # root (see {DataRoot}). Pass +data_root:+ or set +ITUOB_DATA_ROOT+;
  # inside a repository checkout neither is needed. A missing or
  # incomplete root raises Ituob::DataRoot::MissingError from +new+, naming
  # the root and how to set it. The root is process-wide, not per provider.
  #
  # Raises UnknownRegisterError, UnknownIssueError or
  # Projections::KeyHistory::UnknownKeyError (all ArgumentError) for input
  # that names nothing; textual registers without a compiled Entry class
  # raise Projections::RegisterItems::UnsupportedRegisterError.
  class Provider
    class UnknownRegisterError < ArgumentError; end
    class UnknownIssueError < ArgumentError; end

    QUERIES = %i[edition history].freeze

    def initialize(data_root: nil)
      DataRoot.configure(data_root) if data_root
      DataRoot.path
    end

    # Queries a document may invoke; nothing else is reachable.
    def lutaml_data_queries
      QUERIES
    end

    def edition(register:, as_of:)
      catalog, items, state = resolve(register, as_of)
      Projections::RegisterEdition.new(
        register: catalog, state: state, items: items.hydrate(state)
      ).to_model
    end

    def history(register:, key:, as_of:)
      catalog, _items, state = resolve(register, as_of)
      Projections::KeyHistory.new(register: catalog, state: state).for_key(key)
    end

    private

    def resolve(register, as_of)
      catalog = find_register(register)
      issue = validate_issue(catalog, as_of)
      items = Projections::RegisterItems.new(register: catalog)
      [catalog, items, state_for(catalog, items, issue)]
    end

    def find_register(name)
      slug = name.to_s
      found = Catalogs::Registers.find_by_slug(slug) || Catalogs::Registers.find(slug)
      return found if found

      raise UnknownRegisterError,
            "Unknown register #{name.inspect}; known: #{Catalogs::Registers.all_slugs.sort.join(', ')}"
    end

    def validate_issue(catalog, as_of)
      issue = Integer(as_of.to_s, 10, exception: false)
      raise UnknownIssueError, "as_of must be an OB issue number, got #{as_of.inspect}" unless issue
      raise UnknownIssueError, "Unknown OB issue #{issue}" unless known_issues.include?(issue)
      return issue unless catalog.seed_issue && issue < catalog.seed_issue

      raise UnknownIssueError,
            "Register #{catalog.register_id} has no edition before its seed issue #{catalog.seed_issue}"
    end

    def known_issues
      @known_issues ||= Dir.children(DataRoot.join('ob-issues'))
                           .grep(/\A\d+\z/).to_set(&:to_i)
    end

    # Replayed states are frozen values; one replay serves edition and
    # history calls for the same register and issue.
    def state_for(catalog, items, issue)
      @states ||= {}
      @states[[catalog.register_id, issue]] ||= items.state_at(issue)
    end
  end
end
