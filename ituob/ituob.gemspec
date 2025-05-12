# frozen_string_literal: true

require_relative "lib/ituob/version"

Gem::Specification.new do |spec|
  spec.name = "ituob"
  spec.version = Ituob::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "ITU Operational Bulletin tools"
  spec.description = "Tools for working with ITU Operational Bulletin service publications"
  spec.homepage = "https://github.com/ituob/service-publications-docs"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.glob("{bin,lib}/**/*") + %w[LICENSE README.adoc]
  spec.bindir = "bin"
  spec.executables = ["ituob"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.0"
  spec.add_dependency "json-schema", "~> 3.0"
  spec.add_dependency "colorize", "~> 0.8"
  spec.add_dependency "lutaml-model", "~> 0.7"
  spec.add_dependency "prosereflect"
end
