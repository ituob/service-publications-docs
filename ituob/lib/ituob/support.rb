# frozen_string_literal: true

# Parent namespace file for +Ituob::Support+. Declares leaf autoloads.
#
# Support holds small, pure utility modules shared across the codebase.
# Each module is stateless and safe to mixin or call directly.

module Ituob
  module Support
    autoload :CorpusTree, 'ituob/support/corpus_tree'
    autoload :DeepFreeze, 'ituob/support/deep_freeze'
    autoload :HashField, 'ituob/support/hash_field'
    autoload :Yaml, 'ituob/support/yaml'
  end
end
