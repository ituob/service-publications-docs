# frozen_string_literal: true

require 'bundler/setup'
require 'ituob'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Per project rules: never use doubles. We use real data instead.
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end

# Real fixture paths (no mocks).
# spec_helper.rb lives at ituob/spec/spec_helper.rb; data lives two levels up
# at service-publications-docs/{itu-ob-data/issues,ob-issues}.
FIXTURE_ROOT = ENV.fetch(
  'ITUOB_FIXTURE_ROOT',
  File.expand_path('../../itu-ob-data/issues', __dir__),
)
OB_ISSUES_ROOT = ENV.fetch(
  'ITUOB_OB_ISSUES_ROOT',
  File.expand_path('../../ob-issues', __dir__),
)

