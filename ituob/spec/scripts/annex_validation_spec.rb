# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

RSpec.describe 'annex validation' do
  describe Ituob::Support::CorpusTree do
    it 'loads and validates a publication named _class' do
      data = { '_class' => { 'position_on' => Date.new(2018, 12, 15) } }

      expect(described_class.resolve_for('annexes.yaml', data)).to eq('IssueAnnexes')
      model = Ituob::Models.const_get(described_class.resolve_for('annexes.yaml', data))
      expect(model.from_yaml(data.to_yaml).to_hash).to eq(data)
    end
  end

  it 'rejects malformed positions and accepts _class publications in the actual annex gate' do
    Dir.mktmpdir('annex-gate') do |root|
      FileUtils.mkdir_p(File.join(root, 'scripts'))
      FileUtils.mkdir_p(File.join(root, 'ituob'))
      FileUtils.ln_s(File.expand_path('../../lib', __dir__), File.join(root, 'ituob/lib'))
      script = File.join(root, 'scripts/validate_data_lml.rb')
      FileUtils.cp(File.expand_path('../../../scripts/validate_data_lml.rb', __dir__), script)
      entries = [nil, true, false, 123, ['2018-12-15'], { 'bad' => 'value' }, 'bogus']
      entries.each_with_index do |value, index|
        dir = File.join(root, 'ob-issues', (index + 1).to_s)
        FileUtils.mkdir_p(dir)
        data = { '_class' => { 'position_on' => value } }
        File.write(File.join(dir, 'annexes.yaml'), data.to_yaml)
      end

      output, status = Open3.capture2e(RbConfig.ruby, script, '--annexes-only')
      expect(status.exitstatus).to eq(1)
      expect(output).to include('files validated: 1', 'FAILURES: 6', 'position_on must be a date, timestamp or null')
      expect(output).not_to include('start_with?')
    end
  end
end
