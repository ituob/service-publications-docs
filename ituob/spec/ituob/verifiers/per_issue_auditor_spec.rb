# frozen_string_literal: true

require 'spec_helper'

# Integration tests for PerIssueAuditor. Uses the real fixture tree.
RSpec.describe Ituob::Verifiers::PerIssueAuditor, :integration do
  subject(:auditor) do
    described_class.new(
      issue_repository: Ituob::Repositories::IssueRepository.new(
        source_root: FIXTURE_ROOT,
        output_root: OB_ISSUES_ROOT,
      ),
    )
  end

  it 'returns a Result with the expected shape' do
    result = auditor.verify
    expect(result).to be_a(Ituob::Verifiers::Base::Result)
    expect(result.name).to eq('PerIssueAuditor')
    expect(result.stats[:issues_complete]).to be_a(Integer)
  end

  it 'reports a non-zero count of complete issues' do
    result = auditor.verify
    expect(result.stats[:issues_complete]).to be > 300
  end

  it 'reports zero issues as incomplete' do
    result = auditor.verify
    expect(result.stats[:issues_incomplete]).to eq(0)
    expect(result.errors).to be_empty
  end
end
