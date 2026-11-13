# frozen_string_literal: true

require 'spec_helper'
require 'date'
require 'ituob/catalogs'

RSpec.describe Ituob::Catalogs::Registers do
  before { described_class.reset! }

  describe '.all_register_ids' do
    it 'lists known registers' do
      ids = described_class.all_register_ids
      expect(ids).to include('E118_IIN', 'E212_MNC', 'M1400_ICC', 'F1')
    end
  end

  describe '.find' do
    it 'returns the entry by register_id' do
      entry = described_class.find('E212_MNC')
      expect(entry.title_en).to include('Mobile Network Codes')
      expect(entry.recommendation).to eq('E.212')
      expect(entry.key_field).to eq('mcc_mnc_codes')
    end

    it 'flags only annex seeds positioned on their issue date' do
      mismatches = []
      described_class.all.select { |entry| entry.seed_issue && !entry.external }.each do |entry|
        root = File.expand_path('../../../../ob-issues', __dir__)
        annexes_path = File.join(root, entry.seed_issue.to_s, 'annexes.yaml')
        unless File.file?(annexes_path)
          expect(entry.seed_includes_seed_issue).to be(false),
            "#{entry.register_id} has no seed-issue annex and cannot include it"
          next
        end

        annexes = Ituob::Support::Yaml.safe_load_file(annexes_path)
        unless annexes.key?(entry.register_id)
          expect(entry.seed_includes_seed_issue).to be(false),
            "#{entry.register_id} has no direct seed-issue annex and cannot include it"
          next
        end

        issue = Ituob::Support::Yaml.safe_load_file(File.join(root, entry.seed_issue.to_s, 'meta.yaml'))
        annex_date = Date.parse(annexes.fetch(entry.register_id).fetch('position_on').to_s)
        issue_date = Date.parse(issue.fetch('publication_date').to_s)

        matches_issue_date = annex_date == issue_date
        next if entry.seed_includes_seed_issue == matches_issue_date

        mismatches << "#{entry.register_id}: flagged=#{entry.seed_includes_seed_issue}, date_match=#{matches_issue_date}"
      end

      expect(mismatches).to be_empty, mismatches.join('; ')
    end

    it 'defaults to replaying seed-issue patches' do
      expect(described_class.find('F1').seed_includes_seed_issue).to be(false)
      expect(described_class.find('E164_NOTE_N').seed_includes_seed_issue).to be(false)
    end
  end

  describe '.find_by_slug' do
    it 'returns the entry by filesystem slug' do
      entry = described_class.find_by_slug('e212-mnc')
      expect(entry.register_id).to eq('E212_MNC')
    end
  end

  describe '.for_recommendation' do
    it 'returns every register created by a recommendation' do
      expect(described_class.for_recommendation('E.212').map(&:register_id).sort)
        .to eq(%w[E212_ICC E212_MNC E212_SHARED_MCC])
    end

    it 'is empty for unknown recommendations' do
      expect(described_class.for_recommendation('Z.999')).to be_empty
    end
  end

  describe 'routed registers' do
    it 'reads amendments from the slug they share with their parent register' do
      note = described_class.find('E164_NOTE_O')

      expect(note.amendment_slug).to eq('e164-cc')
      expect(described_class.find('E164_CC').amendment_slug).to eq('e164-cc')
    end

    it 'claims the rows whose routed field starts with the prefix' do
      note = described_class.find('E164_NOTE_O')

      expect(note.routes?('cc_ic' => '+882 13')).to be(true)
      expect(note.routes?('cc_ic' => '+883 100')).to be(false)
      expect(described_class.find('E164_CC').routes?('cc_ic' => '+882 13')).to be(false)
    end
  end

  describe '.slug_for' do
    it 'returns the catalogued slug for known IDs' do
      expect(described_class.slug_for('E212_MNC')).to eq('e212-mnc')
    end

    it 'derives a slug for unknown IDs' do
      expect(described_class.slug_for('Z999_New_Thing')).to eq('z999-new-thing')
    end
  end
end

RSpec.describe Ituob::Catalogs::Recommendations do
  before { described_class.reset! }

  describe '.all' do
    it 'lists known recommendations' do
      codes = described_class.all.map(&:code)
      expect(codes).to include('E.212', 'E.164', 'M.1400', 'F.1')
    end
  end

  describe '.find' do
    it 'returns the entry by code' do
      entry = described_class.find('E.212')
      expect(entry.title_en).to include('international identification plan')
      expect(entry.bureau).to eq('ITU-T')
    end
  end
end
