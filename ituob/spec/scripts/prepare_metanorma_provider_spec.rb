# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../scripts/prepare_metanorma_provider'

RSpec.describe MetanormaProviderSetup do
  around do |example|
    Dir.mktmpdir do |directory|
      @gemfile = File.join(directory, 'Gemfile')
      example.run
    end
  end

  let(:provider_path) { '/workspace/service-publications-docs/ituob' }

  it 'replaces the old plugin pin while preserving native gem declarations' do
    source = <<~GEMFILE
      source 'https://rubygems.org'
      gem 'nokogiri', '= 1.18.10'
      gem 'metanorma-plugin-lutaml', '= 0.7.69'
      gem 'json', '= 2.13.2'
    GEMFILE
    File.write(@gemfile, source)

    described_class.prepare_gemfile(@gemfile, provider_path)
    result = File.read(@gemfile)

    expect(result).to include('gem "metanorma-plugin-lutaml", "0.7.80"',
                              'gem "ituob", path: "/workspace/service-publications-docs/ituob"',
                              "gem 'nokogiri', '= 1.18.10'", "gem 'json', '= 2.13.2'")
    expect(result).not_to include('0.7.69')
    RubyVM::InstructionSequence.compile(result)
  end

  it 'adds missing provider dependencies once and updates an existing local path' do
    File.write(@gemfile, "source 'https://rubygems.org'\ngem 'ituob', path: '/old/ituob'\n")

    2.times { described_class.prepare_gemfile(@gemfile, provider_path) }
    result = File.read(@gemfile)

    expect(result.scan(/^gem "ituob"/).size).to eq(1)
    expect(result.scan(/^gem "metanorma-plugin-lutaml"/).size).to eq(1)
    expect(result).not_to include('/old/ituob')
  end

  it 'fails without changing a multiline plugin declaration' do
    source = "gem 'metanorma-plugin-lutaml', # image pin\n  '= 0.7.69'\n"
    File.write(@gemfile, source)

    expect { described_class.prepare_gemfile(@gemfile, provider_path) }
      .to raise_error(RuntimeError, /Multiline metanorma-plugin-lutaml declaration/)
    expect(File.read(@gemfile)).to eq(source)
  end

  it 'fails without changing duplicate plugin declarations' do
    source = "gem 'metanorma-plugin-lutaml'\ngem 'metanorma-plugin-lutaml', '= 0.7.69'\n"
    File.write(@gemfile, source)

    expect { described_class.prepare_gemfile(@gemfile, provider_path) }
      .to raise_error(RuntimeError, /Duplicate metanorma-plugin-lutaml declarations/)
    expect(File.read(@gemfile)).to eq(source)
  end
end
