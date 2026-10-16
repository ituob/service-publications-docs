#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Localization coverage audit across all datasets.
#
# Thin wrapper around +Ituob::Verifiers::LocalizationAuditor+.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'

datasets_root = ENV.fetch('DATASETS_ROOT',
                          File.expand_path('../datasets', __dir__))
dataset_repo = Ituob::Repositories::DatasetRepository.new(root: datasets_root)

auditor = Ituob::Verifiers::LocalizationAuditor.new(dataset_repository: dataset_repo)
result = auditor.verify

report = Ituob::Reporting::Report.new([result])
report.write_summary
