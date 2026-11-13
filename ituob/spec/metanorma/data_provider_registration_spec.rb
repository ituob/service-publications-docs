# frozen_string_literal: true

require 'spec_helper'

# metanorma-plugin-lutaml is not in this bundle (ituob must not depend on
# it); a minimal stand-in records what the discovery file registers.
RSpec.describe 'metanorma/plugin/lutaml/data_providers/ituob' do
  let(:registry) do
    Module.new do
      class << self
        attr_reader :factories

        def register(name, &factory)
          (@factories ||= {})[name] = factory
        end
      end
    end
  end
  let(:file) { Gem.find_files('metanorma/plugin/lutaml/data_providers/ituob.rb').first }

  before do
    stub_const('Metanorma::Plugin::Lutaml::DataProviders', registry)
    load file
  end

  it 'is discoverable through the gem load path' do
    expect(file).to end_with('lib/metanorma/plugin/lutaml/data_providers/ituob.rb')
  end

  it 'registers exactly the "ituob" name with a factory building a provider' do
    expect(registry.factories.keys).to eq(['ituob'])
    expect(registry.factories['ituob'].call).to be_a(Ituob::Provider)
  end
end
