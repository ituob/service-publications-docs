# frozen_string_literal: true

require 'spec_helper'
require 'ituob/normalizers'

RSpec.describe Ituob::Normalizers::Pipeline do
  FakeRepo = Struct.new(:issue_ids) do
    def each_output_issue_id
      issue_ids.each { |iid| yield iid }
    end
  end

  FakeStep = Struct.new(:issue_repository, :applied) do
    def initialize(issue_repository:)
      super(issue_repository, [])
    end

    def apply_to_all
      applied << issue_repository.issue_ids
      self
    end
  end

  let(:repo) { FakeRepo.new(%w[1001 1002]) }

  describe '#run' do
    it 'runs every step against all issues' do
      step = Class.new(FakeStep)
      pipeline = described_class.new(issue_repository: repo, steps: [step])

      results = pipeline.run

      expect(results.length).to eq(1)
      expect(results.first.applied).to eq([%w[1001 1002]])
    end

    it 'runs multiple steps in order' do
      step_a = Class.new(FakeStep)
      step_b = Class.new(FakeStep)
      pipeline = described_class.new(issue_repository: repo, steps: [step_a, step_b])

      results = pipeline.run

      expect(results.length).to eq(2)
      expect(results).to all(be_a(FakeStep))
    end
  end

  describe '#run_step' do
    it 'runs a single step' do
      pipeline = described_class.new(issue_repository: repo, steps: [FakeStep])
      result = pipeline.run_step(FakeStep)
      expect(result).to be_a(FakeStep)
    end
  end

  describe 'DEFAULT_STEPS' do
    it 'includes all 7 normalizer classes' do
      expect(described_class::DEFAULT_STEPS.length).to eq(7)
    end

    it 'starts with FilenameCanonicalizer' do
      expect(described_class::DEFAULT_STEPS.first).to be(Ituob::Normalizers::FilenameCanonicalizer)
    end

    it 'ends with EmptyAmendmentPlaceholder' do
      expect(described_class::DEFAULT_STEPS.last).to be(Ituob::Normalizers::EmptyAmendmentPlaceholder)
    end
  end
end
