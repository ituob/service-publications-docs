# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'date'
require 'ituob/support'

RSpec.describe Ituob::Support::Yaml do
  let(:tmpdir) { Dir.mktmpdir('support-yaml-spec') }
  after { FileUtils.rm_rf(tmpdir) }

  def write_yaml(name, contents)
    path = File.join(tmpdir, name)
    File.write(path, contents)
    path
  end

  describe '.safe_load_file' do
    it 'parses a basic YAML mapping' do
      path = write_yaml('basic.yaml', "---\nkey: value\n")
      expect(described_class.safe_load_file(path)).to eq({ 'key' => 'value' })
    end

    it 'returns nil for an empty file' do
      path = write_yaml('empty.yaml', '')
      expect(described_class.safe_load_file(path)).to be_nil
    end

    it 'reads files as UTF-8 (preserves non-ASCII characters)' do
      path = write_yaml('utf8.yaml', "---\nname: François\n")
      expect(described_class.safe_load_file(path)['name']).to eq('François')
    end

    it 'resolves YAML aliases (anchors and references)' do
      yaml = <<~YAML
        ---
        defaults: &defaults
          timeout: 30
          retries: 3
        production:
          <<: *defaults
          retries: 5
      YAML
      path = write_yaml('aliases.yaml', yaml)
      data = described_class.safe_load_file(path)
      expect(data['production']['timeout']).to eq(30)
      expect(data['production']['retries']).to eq(5)
    end

    it 'deserializes Date objects' do
      path = write_yaml('date.yaml', "---\nday: 2024-03-15\n")
      result = described_class.safe_load_file(path)
      expect(result['day']).to eq(Date.new(2024, 3, 15))
    end

    it 'deserializes Time objects' do
      path = write_yaml('time.yaml', "---\nat: 2024-03-15T10:30:00\n")
      result = described_class.safe_load_file(path)
      expect(result['at']).to be_a(Time)
    end

    it 'deserializes Symbol objects' do
      path = write_yaml('symbol.yaml', "---\nkey: !ruby/symbol foo\n")
      result = described_class.safe_load_file(path)
      expect(result['key']).to eq(:foo)
    end

    it 'rejects disallowed classes (security guard)' do
      # Arbitrary class instantiation via !ruby/object:Class is blocked
      # by safe_load when the class isn't in permitted_classes.
      yaml = "---\nobj: !ruby/object:File {}\n"
      path = write_yaml('evil.yaml', yaml)
      expect { described_class.safe_load_file(path) }.to raise_error(Psych::DisallowedClass)
    end
  end

  describe '.safe_load_string' do
    it 'parses a YAML string the same way as a file' do
      expect(described_class.safe_load_string("---\nkey: value\n"))
        .to eq({ 'key' => 'value' })
    end

    it 'returns nil for an empty string' do
      expect(described_class.safe_load_string('')).to be_nil
    end
  end
end
