# frozen_string_literal: true

require 'spec_helper'
require 'ituob/normalizers'

RSpec.describe 'Ituob::Normalizers structural verification' do
  IssueRepo = Struct.new(:issue_ids) do
    def each_output_issue_id
      issue_ids.each { |iid| yield iid }
    end
  end

  let(:repo) { IssueRepo.new(%w[1001]) }

  normalizer_classes = [
    Ituob::Normalizers::EmptyDirFiller,
    Ituob::Normalizers::EmptyAmendmentPlaceholder,
    Ituob::Normalizers::FilenameCanonicalizer,
    Ituob::Normalizers::PhantomCleanup,
    Ituob::Normalizers::ActionSplitter,
    Ituob::Normalizers::ActionMerger,
    Ituob::Normalizers::OrphanPhantomToFallback,
  ]

  normalizer_classes.each do |klass|
    describe klass.name do
      it 'inherits from Normalizers::Base' do
        expect(klass.ancestors).to include(Ituob::Normalizers::Base)
      end

      it 'responds to apply_to' do
        expect(klass.instance_method(:apply_to)).not_to be_nil
      end

      it 'responds to apply_to_all' do
        expect(klass.instance_method(:apply_to_all)).not_to be_nil
      end

      it 'has a human-readable name' do
        instance = klass.new(issue_repository: repo)
        expect(instance.name).to be_a(String)
        expect(instance.name).not_to be_empty
      end

      it 'accepts issue_repository keyword' do
        expect { klass.new(issue_repository: repo) }.not_to raise_error
      end
    end
  end

  describe Ituob::Normalizers::Pipeline::DEFAULT_STEPS do
    it 'includes all 7 normalizer classes' do
      expect(Ituob::Normalizers::Pipeline::DEFAULT_STEPS.length).to eq(7)
    end

    it 'all steps inherit from Base' do
      Ituob::Normalizers::Pipeline::DEFAULT_STEPS.each do |step|
        expect(step.ancestors).to include(Ituob::Normalizers::Base),
                                     "#{step.name} should inherit from Base"
      end
    end

    it 'no duplicate steps' do
      steps = Ituob::Normalizers::Pipeline::DEFAULT_STEPS
      expect(steps.uniq.length).to eq(steps.length)
    end
  end

  describe Ituob::Normalizers::Base do
    it 'raises NotImplementedError for apply_to' do
      base = described_class.new(issue_repository: IssueRepo.new([]))
      expect { base.apply_to('1001') }.to raise_error(NotImplementedError)
    end

    it 'applies apply_to_all over an empty corpus without error' do
      # Self-contained repo: a shared top-level IssueRepo constant is
      # redefined by other spec files at suite load, shadowing the one
      # above. Build the struct inline so this example cannot see it.
      repo = Struct.new(:issue_ids) do
        def each_output_issue_id
          issue_ids.each { |iid| yield iid }
        end
      end.new([])
      base = described_class.new(issue_repository: repo)
      expect { base.apply_to_all }.not_to raise_error
    end
  end
end
