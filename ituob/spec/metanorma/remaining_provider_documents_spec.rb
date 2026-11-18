# frozen_string_literal: true

require 'spec_helper'
require 'digest'
require 'json'
require_relative '../support/provider_publication_rendering'

RSpec.describe 'Remaining provider publication documents' do
  include ProviderPublicationRendering

  let(:root) { File.expand_path('../../..', __dir__) }
  let(:provider) { Ituob::Provider.new(data_root: root) }
  # Complete AsciiDoc expanded at 8f19d30c, including RR.25.1 loadfile sidecars.
  # Each intentional label change is explicit; reversing only those must restore
  # the original byte digest (including all rows, prose and whitespace).
  JSON.parse(File.read(File.join(__dir__, '../fixtures/publication_tables/remaining_main_sha256.json')))
      .fetch('documents').each do |name, expected|
    it "preserves the complete rendered AsciiDoc for #{name}" do
      path = Dir.glob(File.join(root, 'documents/T-SP-*', name)).fetch(0)
      source = File.read(path)
      actual = render_provider_publication(source, File.dirname(path), provider)

      expect(source).not_to include('[yaml2text', 'data.yaml', 'metadata.yaml')
      expect(actual).not_to include('Liquid error', '{%', '{{', '[lutaml_data')
      expect(Digest::SHA256.hexdigest(actual)).to eq(expected.fetch('expected_sha256'))
      preserved = actual.dup
      expected.fetch('intended_changes', []).each do |change|
        expect(preserved.scan(Regexp.new(Regexp.escape(change.fetch('after')))).size).to eq(change.fetch('count'))
        preserved = preserved.gsub(change.fetch('after'), change.fetch('before'))
      end
      expect(Digest::SHA256.hexdigest(preserved)).to eq(expected.fetch('sha256'))
    end
  end
end
