#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Cross-reference validation across all datasets and change objects.
#
# Thin wrapper around +Ituob::Verifiers::ReferenceVerifier+.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'

source_root = ENV.fetch('ITU_OB_DATA_ROOT',
                        File.expand_path('../itu-ob-data/issues', __dir__))
output_root = ENV.fetch('OB_ISSUES_OUT_PATH',
                        File.expand_path('../ob-issues', __dir__))
datasets_root = ENV.fetch('DATASETS_ROOT',
                          File.expand_path('../datasets', __dir__))

issue_repo = Ituob::Repositories::IssueRepository.new(
  source_root: source_root,
  output_root: output_root,
)
dataset_repo = Ituob::Repositories::DatasetRepository.new(root: datasets_root)

verifier = Ituob::Verifiers::ReferenceVerifier.new(
  issue_repository: issue_repo,
  dataset_repository: dataset_repo,
)
result = verifier.verify

report = Ituob::Reporting::Report.new([result])
report.write_summary
exit(result.passed? ? 0 : 1)
