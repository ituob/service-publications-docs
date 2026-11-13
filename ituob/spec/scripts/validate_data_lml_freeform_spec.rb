# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'yaml'

RSpec.describe 'validate_data_lml freeform inventory' do
  let(:file) { '1000/misc_communications/1.yaml' }
  let(:asset) { 'sources/message.adoc' }
  let(:contents) { 'message.adoc' }
  let(:inventory) do
    [{ 'file' => file, 'source_asset' => asset, 'reason' => 'AsciiDoc source reference' }]
  end
  let(:arguments) { ['--all'] }
  let(:result) { Open3.capture3(RbConfig.ruby, File.join(@root, 'scripts/validate_data_lml.rb'), *arguments) }

  around do |example|
    Dir.mktmpdir('freeform-validation') do |root|
      @root = root
      ['scripts', 'catalogs', File.dirname("ob-issues/#{file}"), 'sources'].each do |dir|
        FileUtils.mkdir_p(File.join(root, dir))
      end
      FileUtils.cp(File.expand_path('../../../scripts/validate_data_lml.rb', __dir__), File.join(root, 'scripts'))
      FileUtils.ln_s(File.expand_path('../..', __dir__), File.join(root, 'ituob'))
      File.write(File.join(root, 'catalogs/freeform_messages.yaml'), inventory.to_yaml)
      File.write(File.join(root, 'ob-issues', file), { 'contents' => contents }.to_yaml)
      File.write(File.join(root, asset), 'Printed message')
      example.run
    end
  end

  it 'accepts listed freeform messages and prints their names and reasons' do
    stdout, stderr, status = result
    expect(status.success?).to be(true), "#{stdout}\n#{stderr}"
    expect(stdout).to include("SKIP #{file}", asset, 'AsciiDoc source reference', 'INSTANCE DATA VALID')
  end

  context 'when the freeform message is unlisted' do
    let(:inventory) { [] }

    it 'fails with the file name' do
      stdout, _stderr, status = result
      expect(status.success?).to be(false)
      expect(stdout).to include(file, 'unlisted freeform general message')
    end
  end

  context 'when a listed message is now structured' do
    let(:contents) { { 'type' => 'doc', 'content' => [] } }

    it 'rejects the stale listing' do
      stdout, _stderr, status = result
      expect(status.success?).to be(false)
      expect(stdout).to include(file, 'listed message is no longer freeform')
    end
  end

  context 'when an unlisted message is structured' do
    let(:contents) { { 'type' => 'doc', 'content' => [] } }
    let(:inventory) { [] }

    it 'continues to validate it through its model' do
      stdout, stderr, status = result
      expect(status.success?).to be(true), "#{stdout}\n#{stderr}"
      expect(stdout).to include('files validated: 1', 'skipped (freeform): 0')
    end
  end

  context 'when a listed file is outside the sample' do
    let(:file) { '1001/misc_communications/1.yaml' }
    let(:arguments) { [] }

    it 'still checks its source asset' do
      %w[999 1002].each { |issue| FileUtils.mkdir_p(File.join(@root, 'ob-issues', issue)) }
      FileUtils.rm(File.join(@root, asset))
      stdout, _stderr, status = result
      expect(status.success?).to be(false)
      expect(stdout).to include(file, 'missing source asset')
    end
  end

  it 'rejects a missing source asset' do
    FileUtils.rm(File.join(@root, asset))
    stdout, _stderr, status = result
    expect(status.success?).to be(false)
    expect(stdout).to include(file, asset, 'missing source asset')
  end

  it 'rejects a listing whose message was deleted' do
    FileUtils.rm(File.join(@root, 'ob-issues', file))
    stdout, _stderr, status = result
    expect(status.success?).to be(false)
    expect(stdout).to include(file, 'listed message is missing')
  end
end
