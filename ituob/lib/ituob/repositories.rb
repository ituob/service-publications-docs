# frozen_string_literal: true

# Parent namespace file for +Ituob::Repositories+.
#
# Repositories abstract disk I/O. They read and write YAML, walk directory
# trees, and yield domain objects. They never apply business logic — that's
# for extractors, normalizers, and verifiers.

module Ituob
  module Repositories
    autoload :IssueRepository, 'ituob/repositories/issue_repository'
    autoload :DatasetRepository, 'ituob/repositories/dataset_repository'
    autoload :ChangeObjectRepository, 'ituob/repositories/change_object_repository'
    autoload :YamlStore, 'ituob/repositories/yaml_store'
  end
end
