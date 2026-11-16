# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'

RSpec.describe 'register snapshot script boot' do
  it 'loads top-level autoloads before reading the register catalog' do
    script = <<~'RUBY'
      load 'scripts/generate_register_snapshots.rb'
    RUBY
    Dir.mktmpdir do |snapshots_dir|
      stdout, stderr, status = Open3.capture3(
        { 'SNAPSHOTS_OUT' => snapshots_dir },
        RbConfig.ruby, '-rbundler/setup', '-Iituob/lib', '-e', script,
        chdir: File.expand_path('../../..', __dir__),
      )

      expect(status).to be_success, stderr
      expect(stdout).to include('Snapshots: 21 registers,')
      expect(stdout).to include('Snapshot integrity: 0 errors, 0 warnings')
    end
  end
end
