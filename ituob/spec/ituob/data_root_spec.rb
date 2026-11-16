# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Ituob::DataRoot do
  let(:checkout) { described_class::CHECKOUT }

  around do |example|
    saved = ENV.fetch(described_class::ENV_KEY, nil)
    ENV.delete(described_class::ENV_KEY)
    described_class.configure(nil)
    example.run
  ensure
    saved ? ENV[described_class::ENV_KEY] = saved : ENV.delete(described_class::ENV_KEY)
    described_class.configure(nil)
  end

  it 'resolves the repository checkout with no configuration' do
    expect(described_class.path).to eq(checkout)
    expect(Ituob::Catalogs::Registers.find('E212_MNC')).not_to be_nil
  end

  it 'prefers the environment variable over the checkout' do
    Dir.mktmpdir do |empty|
      ENV[described_class::ENV_KEY] = empty
      expect { described_class.path }
        .to raise_error(described_class::MissingError, /#{Regexp.escape(empty)}.*from ITUOB_DATA_ROOT/)
    end
  end

  it 'prefers an explicit root over the environment variable' do
    ENV[described_class::ENV_KEY] = '/nonexistent/ituob'
    described_class.configure(checkout)
    expect(described_class.path).to eq(checkout)
  end

  context 'when nothing is configured and there is no checkout (installed gem)' do
    before { stub_const("#{described_class}::CHECKOUT", '/nonexistent/gem/dir') }

    it 'raises an error naming the variable and the keyword' do
      expect { described_class.path }
        .to raise_error(described_class::MissingError, /ITUOB_DATA_ROOT.*data_root:/)
    end

    it 'does not fall through to an Errno from the catalog' do
      Ituob::Catalogs::Registers.reset!
      expect { Ituob::Catalogs::Registers.find('E212_MNC') }
        .to raise_error(described_class::MissingError)
    end
  end

  it 'lists what an incomplete root lacks' do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'ob-issues'))
      described_class.configure(root)
      expect { described_class.path }
        .to raise_error(described_class::MissingError, %r{missing catalogs/registers.yaml, datasets})
    end
  end

  it 'reloads the catalog from the new root when the root changes' do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(%w[catalogs datasets ob-issues].map { |d| File.join(root, d) })
      File.write(File.join(root, 'catalogs', 'registers.yaml'),
                 { 'registers' => [{ 'register_id' => 'X_TEST', 'slug' => 'x-test' }] }.to_yaml)
      expect(Ituob::Catalogs::Registers.find('E212_MNC')).not_to be_nil
      described_class.configure(root)
      expect(Ituob::Catalogs::Registers.all_slugs).to eq(['x-test'])
      described_class.configure(nil)
      expect(Ituob::Catalogs::Registers.find('E212_MNC')).not_to be_nil
    end
  end
end
