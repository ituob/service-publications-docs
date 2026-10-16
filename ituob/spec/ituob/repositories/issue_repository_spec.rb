# frozen_string_literal: true

require 'spec_helper'

# Integration tests that hit the real itu-ob-data fixture tree. Marked
# :integration so they can be filtered out in fast test runs.
RSpec.describe Ituob::Repositories::IssueRepository, :integration do
  subject(:repo) do
    described_class.new(
      source_root: FIXTURE_ROOT,
      output_root: OB_ISSUES_ROOT,
    )
  end

  describe '#each_source_issue_id' do
    it 'yields every issue directory' do
      count = repo.each_source_issue_id.count
      # We expect 389 issues in the production fixture; allow flexibility
      # for staged environments.
      expect(count).to be >= 360
    end

    it 'yields IssueId objects' do
      first = repo.each_source_issue_id.first
      expect(first).to be_a(Ituob::Domain::Identifiers::IssueId)
    end
  end

  describe '#read_meta / #read_general / #read_amendments' do
    let(:sample_id) { Ituob::Domain::Identifiers::IssueId.new(1000) }

    it 'reads meta.yaml' do
      meta = repo.read_meta(sample_id)
      expect(meta).to be_a(Hash)
      expect(meta['id']).to eq(1000)
    end

    it 'reads general.yaml' do
      general = repo.read_general(sample_id)
      expect(general).to be_a(Hash)
      expect(general['messages']).to be_an(Array)
    end

    it 'reads amendments.yaml' do
      amendments = repo.read_amendments(sample_id)
      expect(amendments).to be_a(Hash)
      expect(amendments['messages']).to be_an(Array)
    end
  end

  describe '#each_dataset_slug' do
    it 'yields every subdirectory under an issue' do
      slugs = []
      repo.each_dataset_slug(Ituob::Domain::Identifiers::IssueId.new(1000)) do |s|
        slugs << s
      end
      expect(slugs).to include('general')
    end
  end
end
