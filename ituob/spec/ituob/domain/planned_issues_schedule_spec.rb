# frozen_string_literal: true

require 'spec_helper'
require 'date'

RSpec.describe Ituob::Domain::PlannedIssuesSchedule do
  describe '.from_planned_issues_array' do
    it 'builds entries from a hash array' do
      array = [
        { 'id' => 1344, 'publication_date' => '2026-07-15', 'cutoff_date' => '2026-07-01' },
        { 'id' => 1345, 'publication_date' => '2026-08-01', 'cutoff_date' => '2026-07-15' },
      ]
      schedule = described_class.from_planned_issues_array(array)
      expect(schedule.entries.length).to eq(2)
      expect(schedule.entries.first.issue_id).to eq(1344)
      expect(schedule.entries.first.publication_date).to eq(Date.iso8601('2026-07-15'))
    end

    it 'returns an empty schedule for nil' do
      schedule = described_class.from_planned_issues_array(nil)
      expect(schedule.entries).to be_empty
    end
  end

  describe '.from_defaults_meta' do
    it 'extracts planned_issues from a meta hash' do
      meta = { 'planned_issues' => [{ 'id' => 1, 'publication_date' => '2026-01-01' }] }
      schedule = described_class.from_defaults_meta(meta)
      expect(schedule.entries.length).to eq(1)
    end
  end

  describe '#upcoming' do
    it 'filters entries with publication_date strictly after as_of' do
      array = [
        { 'id' => 1, 'publication_date' => '2020-01-01' },
        { 'id' => 2, 'publication_date' => '2030-01-01' },
      ]
      schedule = described_class.from_planned_issues_array(array)
      upcoming = schedule.upcoming(as_of: Date.iso8601('2025-01-01'))
      expect(upcoming.length).to eq(1)
      expect(upcoming.first.issue_id).to eq(2)
    end
  end

  describe '#next_n' do
    it 'returns the first n upcoming entries' do
      array = (1..10).map do |i|
        { 'id' => i, 'publication_date' => "2030-0#{i}-01" }
      end
      schedule = described_class.from_planned_issues_array(array)
      expect(schedule.next_n(3, as_of: Date.iso8601('2025-01-01')).length).to eq(3)
    end
  end
end
