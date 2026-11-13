# frozen_string_literal: true

module Ituob
  # Locates the data tree the register projections read.
  #
  # The data root is a directory laid out like the service-publications-docs
  # repository and holding at least:
  #
  #   catalogs/registers.yaml   register catalog
  #   datasets/                 seed + change files named by the catalog
  #   ob-issues/                one directory per OB issue
  #
  # Resolution order:
  #
  # 1. a path passed to {.configure} (e.g. via +Provider.new(data_root:)+);
  # 2. the +ITUOB_DATA_ROOT+ environment variable;
  # 3. the repository checkout this file lives in (+ituob/lib/ituob/..+),
  #    which keeps a working copy running with no configuration.
  #
  # An installed gem carries none of this data, so it resolves to nothing
  # and {.path} raises {MissingError} naming the root and how to set it.
  #
  # The root is process-wide: the catalogs are singletons loaded from it.
  module DataRoot
    ENV_KEY = 'ITUOB_DATA_ROOT'
    REQUIRED = %w[catalogs/registers.yaml datasets ob-issues].freeze
    CHECKOUT = File.expand_path('../../..', __dir__)

    class MissingError < ArgumentError; end

    class << self
      # Pins the root (nil returns to ENV / checkout resolution). Switching
      # roots drops the catalog cache so the next lookup reads the new tree.
      def configure(path)
        path = path&.to_s
        return if path == @configured

        @configured = path
        Catalogs::Registers.reset!
      end

      # Validated absolute data root.
      def path
        candidate, source = candidate_root
        raise MissingError, missing_message(nil, source) unless candidate

        root = File.expand_path(candidate)
        missing = REQUIRED.reject { |rel| File.exist?(File.join(root, rel)) }
        return root if missing.empty?

        raise MissingError, missing_message(root, source, missing)
      end

      def join(*parts)
        File.join(path, *parts)
      end

      private

      def candidate_root
        return [@configured, 'the configured data root'] if @configured
        return [ENV.fetch(ENV_KEY), ENV_KEY] if ENV[ENV_KEY] && !ENV[ENV_KEY].empty?

        [CHECKOUT, 'the repository checkout'] if File.exist?(File.join(CHECKOUT, REQUIRED.first))
      end

      def missing_message(root, source, missing = nil)
        how = "Set #{ENV_KEY}=/path/to/service-publications-docs or pass " \
              'data_root: to Ituob::Provider.new'
        return "No ITU OB data root found (the installed gem ships no data). #{how}." unless root

        "Data root #{root.inspect} (from #{source}) is missing #{missing.join(', ')}. #{how}."
      end
    end
  end
end
