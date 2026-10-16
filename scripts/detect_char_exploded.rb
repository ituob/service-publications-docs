#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Detect char-exploded YAML serialization in source files.
#
# Thin wrapper around +Ituob::Verifiers::CharExplodedDetector+.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'

source_root = ENV.fetch('ITU_OB_DATA_ROOT',
                        File.expand_path('../itu-ob-data/issues', __dir__))
output_root = ENV.fetch('OB_ISSUES_OUT_PATH',
                        File.expand_path('../ob-issues', __dir__))

issue_repo = Ituob::Repositories::IssueRepository.new(
  source_root: source_root,
  output_root: output_root,
)

verifier = Ituob::Verifiers::CharExplodedDetector.new(issue_repository: issue_repo)
result = verifier.verify

report = Ituob::Reporting::Report.new([result])
report.write_summary
exit(result.passed? ? 0 : 1)
