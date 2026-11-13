#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob/verifiers'

result = Ituob::Verifiers::RegisterStateIntegrityVerifier.new.verify
result.details.group_by { |detail| detail[:register_id] }.each do |register_id, states|
  current = states.find { |detail| detail[:ob_issue] == 'current' }
  historical = states.reject { |detail| detail[:ob_issue] == 'current' }
  historical_count = historical.sum { |detail| detail[:invalid_entry_count] }
  puts "#{register_id}: current #{current[:invalid_entry_count]}/#{current[:entry_count]} invalid entries; " \
       "historical #{historical_count} invalid entries across #{historical.length} editions"
end
result.errors.each { |error| warn error }
puts "#{result.stats[:registers_checked]} registers checked; #{result.errors.length} errors"
exit(result.passed? ? 0 : 1)
