# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

RSpec.describe 'scripts/build_ob_issues.rb NBSP policy' do
  let(:printed_text) { "Printed\u00a0text" }

  before(:context) do
    repo_root = File.expand_path('../../..', __dir__)
    Dir.mktmpdir('nbsp-spec') do |dir|
      code = <<~'CODE'
        Ituob::Catalogs::Registers.all.each do |register|
          fields = [register.key_field, register.fallback_key_fields].flatten.compact
          row = fields.to_h { |field| [field, { 'en' => "12\u00a034", 'fr' => "56\u00a078" }] }
          row['printed_text'] = "Printed\u00a0text"
          patch = write_change_object(
            issue_id: 1000, dataset_slug: register.amendment_slug, seq: '001',
            date_active: '2020-01-01', identifier: { 'code' => "P\u00a019" },
            data: { 'entries' => [row], 'notes' => ["Printed\u00a0text"], 'caption' => "Printed\u00a0text" },
            description: "Printed\u00a0text"
          )
          write_yaml(File.join(ARGV[0], "#{register.register_id}.yaml"), patch)
        end
      CODE
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, '-r', File.join(repo_root, 'scripts/build_ob_issues.rb'), '-e', code, dir
      )
      expect(status.success?).to be(true), stderr
      @patches = Dir.glob(File.join(dir, '*.yaml')).to_h do |path|
        [File.basename(path, '.yaml'), YAML.load_file(path)]
      end
    end
  end

  Ituob::Catalogs::Registers.all.each do |register|
    it "cleans written keys for #{register.register_id} and preserves text" do
      patch = @patches.fetch(register.register_id)
      fields = [register.key_field, register.fallback_key_fields].flatten.compact
      expect(patch['identifier']).to eq('code' => 'P 19')
      fields.each do |field|
        expect(patch.dig('data', 'entries', 0, field)).to eq('en' => '12 34', 'fr' => '56 78')
      end
      expect(patch.dig('data', 'entries', 0, 'printed_text')).to eq(printed_text)
      expect(patch.dig('data', 'notes')).to eq([printed_text])
      expect(patch.dig('data', 'caption')).to eq(printed_text)
      expect(patch['description']).to eq(printed_text)
    end
  end
end
