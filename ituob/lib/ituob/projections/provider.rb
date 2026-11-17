# frozen_string_literal: true

module Ituob
  # Data provider for metanorma-plugin-lutaml `lutaml_data` blocks.
  #
  #   provider = Ituob::Provider.new
  #   provider.edition(register: 'e212-mnc', as_of: 1170)
  #   provider.publication(register: 'm1400-icc', as_of: 1060)
  #   provider.history(register: 'e212-mnc', key: '234 | 15', as_of: 1170)
  #   provider.actions(register: 'e212-mnc', as_of: 1170)
  #   provider.locale(register: 'e212-mnc')
  #
  # +register+ is the catalog slug (`e212-mnc`) or register id
  # (`E212_MNC`); +as_of+ is an OB issue number. Queries return
  # lutaml-model objects (Models::RegisterEdition, Models::RegisterKeyHistory,
  # Models::RegisterActions)
  # carrying ProjectionProvenance, so they reach Liquid through to_liquid.
  # +publication+ returns every typed seed row in its published order, including
  # shared identifiers, without applying amendments. It accepts only the seed
  # issue; +edition+ returns replayed membership as of any supported issue.
  # Publications require valid current +metadata+ labels; editions carry them
  # when available. Empty publication seeds and fields lost during typed
  # hydration raise ArgumentError rather than producing incomplete tables.
  # +locale+ takes no issue: it returns Models::RegisterLocale, the labels
  # of the dataset's current metadata.yaml, in every language.
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
    class InvalidPublicationMetadataError < ArgumentError; end

    QUERIES = %i[edition publication history actions locale].freeze

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
      edition = Projections::RegisterEdition.new(
        register: catalog, state: state, items: items.hydrate(state),
        source_contexts: items.source_contexts_at(state.at_ob_issue)
      ).to_model
      edition.metadata = edition_metadata(catalog)
      edition
    end

    # The original publication's complete ordered rows, including shared codes.
    # Unlike edition, this does not apply amendments or collapse identifiers.
    def publication(register:, as_of:)
      catalog = find_register(register)
      issue = validate_issue(catalog, as_of)
      unless catalog.seed_issue == issue
        raise UnknownIssueError,
              "Register #{catalog.register_id} publication is only available at its seed issue #{catalog.seed_issue}"
      end

      Models::RegisterEdition.new(
        provenance: Models::ProjectionProvenance.new(
          register_id: catalog.register_id, as_of_issue: issue,
          seed_issue: issue, last_change_issue: issue
        ),
        items: Projections::RegisterItems.new(register: catalog).seed_items,
        metadata: publication_metadata(catalog)
      )
    end

    def history(register:, key:, as_of:)
      catalog, _items, state = resolve(register, as_of)
      Projections::KeyHistory.new(register: catalog, state: state).for_key(key)
    end

    def actions(register:, as_of:)
      catalog, _items, state = resolve(register, as_of)
      Projections::RegisterActions.new(register: catalog, state: state).to_model
    end

    # Per-language title and terms of the register's dataset, read from
    # its metadata.yaml. Every language is returned; the template picks
    # one (`metadata.locale | where: "key", "networks" | map: lang`).
    def locale(register:)
      Projections::RegisterLocale.new(register: find_register(register)).to_model
    end

    private

    def publication_metadata(catalog)
      # Unlike replayed editions, publication templates consume these labels.
      # Missing or malformed metadata must fail before Liquid renders blanks.
      metadata = Projections::RegisterLocale.new(register: catalog)
      path = DataRoot.join(catalog.seed_path, 'metadata.yaml')
      return metadata.to_model unless File.file?(path)

      data = Ituob::Support::Yaml.safe_load_file(path)
      valid = data.is_a?(Hash) && !data.empty?
      if valid
        title = data['title']
        locale = data['locale']
        valid = (!title.nil? || !locale.nil?) &&
          (!data.key?('title') || (title.is_a?(Hash) && !title.empty?)) &&
          (!data.key?('locale') || (locale.is_a?(Array) && locale.all? do |label|
            label.is_a?(Hash) && label['key'].is_a?(String) && !label['key'].empty?
          end))
      end
      unless valid
        raise InvalidPublicationMetadataError, "Register #{catalog.register_id} has invalid publication metadata at #{path}"
      end

      model = metadata.to_model
      projected = model.to_hash
      validate_publication_labels!(catalog, data['title'], projected['title']) if data['title']
      Array(data['locale']).zip(Array(projected['locale'])).each do |labels, rendered|
        validate_publication_labels!(catalog, labels, rendered)
      end
      model
    end

    def validate_publication_labels!(catalog, labels, projected)
      labels.each do |key, value|
        next if value.nil?

        canonical_key = Projections::RegisterLocale::LANGUAGE_ALIASES.fetch(key, key)
        next if projected.is_a?(Hash) && projected.key?(canonical_key)

        raise InvalidPublicationMetadataError,
              "Register #{catalog.register_id} publication metadata loses #{key}"
      end
    end

    def edition_metadata(catalog)
      Projections::RegisterLocale.new(register: catalog).to_model
    rescue Projections::RegisterLocale::MissingMetadataError
      nil
    end

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
