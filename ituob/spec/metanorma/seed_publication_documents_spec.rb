# frozen_string_literal: true

require 'spec_helper'
require 'liquid'
require 'digest'
require 'json'
require 'tmpdir'
require_relative '../support/provider_publication_rendering'

RSpec.describe 'Seed publication provider documents' do
  include ProviderPublicationRendering

  let(:root) { File.expand_path('../../..', __dir__) }
  let(:provider) { Ituob::Provider.new(data_root: root) }
  # Byte-for-byte table output captured from 7d94b1c1 with the original YAML
  # rows, metadata and templates, before replacing yaml2text sources.
  let(:expected) do
    JSON.parse(File.read(File.join(__dir__, '../fixtures/publication_tables/seed_table_sha256.json')))
  end

  [['E.118-2018', 'e118-iin', 1161], ['E.218-2017', 'e218-trcc', 1125],
   ['M.1400-2014', 'm1400-icc', 1060]].each do |publication, slug, issue|
    context publication do
      let(:directory) { File.join(root, "documents/T-SP-#{publication}") }
      let(:edition) { provider.publication(register: slug, as_of: issue) }

      { 'E' => 'en', 'F' => 'fr', 'S' => 'es', 'A' => 'ar', 'R' => 'ru', 'C' => 'zh' }.each do |suffix, language|
        it "preserves the complete #{language} table from the seed publication" do
          source = File.read(File.join(directory, "T-SP-#{publication}-#{suffix}.adoc"))
          expect(source).to include('provider:ituob.publication', "\"register\":\"#{slug}\"", "\"as_of\":#{issue}")
          expect(source).not_to include('yaml2text', 'data.yaml', 'metadata.yaml')
          expect(source).to include('data: edition.items, metadata: edition.metadata')
          table = render_publication_table(directory, 'table', edition.items, edition.metadata, language)
          expect(Digest::SHA256.hexdigest(table)).to eq(expected.fetch(slug).fetch(language))
        end
      end
    end
  end

  it 'preserves distinct companies sharing a carrier code' do
    edition = provider.publication(register: 'm1400-icc', as_of: 1060)
    shared = edition.items.select { |item| item.carrier_code == 'MOC' }

    expect(edition.items.size).to eq(1164)
    expect(shared.map { |item| item.country_or_area.en }).to include('Afghanistan', 'Uzbekistan (Republic of)')
  end

  it 'fails clearly when the publication seed is absent' do
    Dir.mktmpdir do |temporary_root|
      %w[catalogs ob-issues].each do |directory|
        File.symlink(File.join(root, directory), File.join(temporary_root, directory))
      end
      FileUtils.mkdir_p(File.join(temporary_root, 'datasets/1060-M.1400'))
      missing = Ituob::Provider.new(data_root: temporary_root)

      expect { missing.publication(register: 'm1400-icc', as_of: 1060) }
        .to raise_error(Ituob::Projections::RegisterItems::MissingSeedError, /M1400_ICC.*no publication seed/)
    ensure
      Ituob::DataRoot.configure(nil)
    end
  end

  it 'rejects issues other than the original publication issue' do
    expect { provider.publication(register: 'e118-iin', as_of: 1162) }
      .to raise_error(Ituob::Provider::UnknownIssueError, /only available at its seed issue 1161/)
  end
end
