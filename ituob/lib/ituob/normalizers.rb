# frozen_string_literal: true

# Parent namespace for normalizers.
#
# Each Normalizer is an idempotent cleanup pass. Running it twice produces
# the same output as running once. Normalizers compose via +Pipeline+.
#
# To add a new normalizer:
#   1. Subclass +Ituob::Normalizers::Base+.
#   2. Implement +#name+ and +#apply_to(issue_id)+.
#   3. Register it in +Pipeline::DEFAULT_STEPS+ (or pass at construction).

module Ituob
  module Normalizers
    autoload :Base, 'ituob/normalizers/base'
    autoload :Pipeline, 'ituob/normalizers/pipeline'
    autoload :PhantomCleanup, 'ituob/normalizers/phantom_cleanup'
    autoload :ActionSplitter, 'ituob/normalizers/action_splitter'
    autoload :ActionMerger, 'ituob/normalizers/action_merger'
    autoload :FilenameCanonicalizer, 'ituob/normalizers/filename_canonicalizer'
    autoload :EmptyAmendmentPlaceholder, 'ituob/normalizers/empty_amendment_placeholder'
    autoload :OrphanPhantomToFallback, 'ituob/normalizers/orphan_phantom_to_fallback'
    autoload :EmptyDirFiller, 'ituob/normalizers/empty_dir_filler'
  end
end
