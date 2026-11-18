# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/provider_publication_rendering'

RSpec.describe 'Three-language provider publications' do
  include ProviderPublicationRendering

  let(:root) { File.expand_path('../../..', __dir__) }
  let(:provider) { Ituob::Provider.new(data_root: root) }

  {
    'T-SP-Q.708B-2016' => ['q708-ispc', 1109, '1109-Q.708B'],
    'T-SP-E.164B-2012' => ['e164-acn', 1015, '1015-E.164B'],
    'T-SP-E.164C-2011' => ['dp', 994, '994-E.164C'],
    'T-SP-X.121B-2011' => ['x121-dnic', 977, '977-X.121B'],
    'T-SP-F.400-2011' => ['f400-admd', 974, '974-F.400']
  }.each do |publication, (register, issue, dataset)|
    context publication do
      let(:directory) { File.join(root, 'documents', publication) }
      let(:edition) { provider.publication(register: register, as_of: issue) }
      let(:legacy_rows) { Ituob::Support::Yaml.safe_load_file(File.join(root, 'datasets', dataset, 'data.yaml')) }
      let(:legacy_metadata) { Ituob::Support::Yaml.safe_load_file(File.join(root, 'datasets', dataset, 'metadata.yaml')) }
      let(:legacy_template) do
        path = if register == 'x121-dnic'
                 File.join(root, 'ituob/spec/fixtures/publications/x121b_legacy_table.liquid')
               else
                 File.join(directory, '_table.liquid')
               end
        File.read(path)
      end

      { 'E' => 'en', 'F' => 'fr', 'S' => 'es' }.each do |suffix, language|
        it "uses typed provider rows and preserves the complete #{language} publication table" do
          source = File.read(Dir.glob(File.join(directory, "*-#{suffix}.adoc")).fetch(0))
          expect(source).to include('provider:ituob.publication', "\"register\":\"#{register}\"", "\"as_of\":#{issue}")
          expect(source).not_to include('yaml2text', 'data2text', 'data.yaml', 'metadata.yaml')

          expected = Liquid::Template.parse(legacy_template).render!(
            'data' => legacy_rows, 'metadata' => legacy_metadata, 'lang' => language
          )
          actual = render_publication_table(directory, 'table', edition.items.map(&:to_liquid), edition.metadata.to_liquid, language)
          expect(edition.items.size).to eq(legacy_rows.size)
          expect(actual).to eq(expected)
          rendered = render_provider_publication(source, directory, provider)
          expect(rendered).to include(actual)
          expect(rendered).not_to include('Liquid error', '{%', '{{', '[lutaml_data')
        end
      end
    end
  end
end
