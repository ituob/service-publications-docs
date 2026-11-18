# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/main_publication_rendering'

RSpec.describe 'Provider publication parity with main' do
  include MainPublicationRendering

  let(:root) { File.expand_path('../../..', __dir__) }
  let(:provider) { Ituob::Provider.new(data_root: root) }
  # Full documents rendered using main's YAML, metadata and Liquid templates.
  # Pinned digests work in shallow CI checkouts without remote branch refs.
  let(:baseline) do
    JSON.parse(File.read(File.join(__dir__, '../fixtures/publication_tables/provider_main_sha256.json')))
      .fetch('documents')
  end

  %w[E.118-2018 E.164B-2012 E.164C-2011 E.164D-2016 E.218-2017
     F.400-2011 M.1400-2014 Q.708A-2017 Q.708B-2016 X.121B-2011].each do |publication|
    context publication do
      suffixes = %w[E.164B-2012 E.164C-2011 F.400-2011 Q.708B-2016 X.121B-2011].include?(publication) ? %w[E F S] : %w[A C E F R S]
      suffixes.each do |suffix|
        name = "T-SP-#{publication}#{%w[F.400-2011 X.121B-2011].include?(publication) ? '-MSW' : ''}-#{suffix}.adoc"

        it "preserves the complete #{name} generated publication" do
          directory = File.join(root, "documents/T-SP-#{publication}")
          actual = render_provider_publication(File.read(File.join(directory, name)), directory, provider)
          expected = baseline.fetch(name)
          restored_notes = publication == 'E.164D-2016'

          expect(actual).not_to include('Liquid error', '{%', '{{', '[lutaml_data')
          expect(publication_content_digest(actual, restored_notes: restored_notes)).to eq(expected.fetch('sha256'))
          if restored_notes
            expected.fetch('note_headings').each { |heading| expect(actual).to include(heading) }
            %w[N O PQ].each do |note|
              rows = Ituob::Support::Yaml.safe_load_file(File.join(root, "datasets/1114-E.164D-Note-#{note}/data.yaml"))
              rows.each do |row|
                %w[applicant network cc_ic status].each do |field|
                  expect(actual).to include(row.fetch(field)) if row[field]
                end
              end
            end
            expect(actual).to include('Iridium Communications Inc.', 'British Telecommunications plc')
          end
        end
      end
    end
  end
end
