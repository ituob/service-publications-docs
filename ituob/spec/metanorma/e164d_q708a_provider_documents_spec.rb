# frozen_string_literal: true

require 'spec_helper'
require 'digest'
require 'json'
require_relative '../support/provider_publication_rendering'

RSpec.describe 'E.164D and Q.708A provider publications' do
  include ProviderPublicationRendering

  let(:root) { File.expand_path('../../..', __dir__) }
  let(:provider) { Ituob::Provider.new(data_root: root) }
  # Captured from the original 7d94b1c1 YAML-backed templates.
  let(:table_digests) do
    JSON.parse(File.read(File.join(__dir__, '../fixtures/publication_tables/e164d_q708a_sha256.json')))
  end

  {
    'T-SP-E.164D-2016' => ['e164-cc', 1114, '1114-E.164D', 'tables'],
    'T-SP-Q.708A-2017' => ['q708-sanc', 1125, '1125-Q.708A', 'table']
  }.each do |publication, (register, issue, dataset, table)|
    context publication do
      let(:directory) { File.join(root, 'documents', publication) }
      let(:edition) { provider.publication(register: register, as_of: issue) }
      let(:legacy_rows) { Ituob::Support::Yaml.safe_load_file(File.join(root, 'datasets', dataset, 'data.yaml')) }

      { 'E' => 'en', 'F' => 'fr', 'S' => 'es', 'A' => 'ar', 'R' => 'ru', 'C' => 'zh' }.each do |suffix, language|
        it "uses only provider data and preserves the #{language} seed tables" do
          source = File.read(File.join(directory, "#{publication}-#{suffix}.adoc"))
          expect(source).to include('provider:ituob.publication', "\"register\":\"#{register}\"", "\"as_of\":#{issue}")
          expect(source).not_to include('yaml2text', 'data.yaml', 'metadata.yaml')

          actual = render_publication_table(directory, table, edition.items.map(&:to_liquid), edition.metadata.to_liquid, language)
          expect(edition.items.size).to eq(legacy_rows.size)
          expect(Digest::SHA256.hexdigest(actual)).to eq(table_digests.fetch(register).fetch(language))

          if language == 'en'
            rendered = render_provider_publication(source, directory, provider)
            expect(rendered).not_to include('Liquid error', '{%', '{{', '[lutaml_data')
            expect(rendered).to include(actual)
            expect(rendered).to include('| 30 | |')
          end
        end
      end
    end
  end

  { 'E' => 'en', 'F' => 'fr', 'S' => 'es', 'A' => 'ar', 'R' => 'ru', 'C' => 'zh' }.each do |suffix, language|
    it "renders the restored E.164D note tables in #{language}" do
      directory = File.join(root, 'documents/T-SP-E.164D-2016')
      source = File.read(File.join(directory, "T-SP-E.164D-2016-#{suffix}.adoc"))
      rendered = render_provider_publication(source, directory, provider)

      %w[n o pq].each do |note|
        edition = provider.publication(register: "e164-note-#{note}", as_of: 1114)
        expect(edition.items).not_to be_empty
        edition.items.each do |item|
          expect(rendered).to include(item.cc_ic, item.network, item.status)
          expect(rendered).to include(item.applicant) if item.applicant
        end
      end
      expect(rendered).to include('Iridium Communications Inc.', 'British Telecommunications plc')
      expect(rendered).to include('[[note_n]]', '[[note_o]]', '[[note_p]]', '[[note_q]]')
      expect(rendered).not_to include('yaml2text', 'file_two', 'file_three', 'file_four')
    end
  end
end
