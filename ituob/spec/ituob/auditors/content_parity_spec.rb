# frozen_string_literal: true

require 'spec_helper'
require 'ituob/auditors'

RSpec.describe Ituob::Auditors::ContentParity do
  let(:auditor) { described_class.new }

  describe '#compare' do
    it 'reports 100% coverage when content is identical' do
      html = '<main><h2>Lists Annexed</h2><p>foo bar baz</p></main>'
      report = auditor.compare(html, html)
      expect(report.coverage).to eq(1.0)
      expect(report.missing_headings).to be_empty
    end

    it 'detects missing tokens' do
      deployed = '<main><h2>Title</h2><p>alpha bravo charlie delta</p></main>'
      actual = '<main><h2>Title</h2><p>alpha bravo</p></main>'
      report = auditor.compare(deployed, actual)
      expect(report.coverage).to be < 1.0
      section = report.sections.first
      expect(section.missing_tokens).to include('charlie', 'delta')
    end

    it 'ignores stop-words and short tokens' do
      deployed = '<main><h2>Title</h2><p>the and for with</p></main>'
      actual = '<main><h2>Title</h2><p></p></main>'
      report = auditor.compare(deployed, actual)
      expect(report.coverage).to eq(1.0)
    end

    it 'detects missing headings' do
      deployed = '<main><h2>Section A</h2><p>alpha</p><h2>Section B</h2><p>bravo</p></main>'
      actual = '<main><h2>Section A</h2><p>alpha</p></main>'
      report = auditor.compare(deployed, actual)
      # Headings are normalized (lowercased, amendment-number-collapsed)
      # before comparison so that the deployed "Amd. no. 19" matches our
      # "Amd. no. 197" (same amendment, different counters).
      expect(report.missing_headings).to include('section b')
    end

    it 'detects missing external links' do
      deployed = '<main><a href="https://itu.int/foo">Link A</a><a href="#anchor">Anchor</a></main>'
      actual = '<main><a href="#anchor">Anchor</a></main>'
      report = auditor.compare(deployed, actual)
      hrefs = report.missing_links.map { |l| l[:href] }
      expect(hrefs).to include('https://itu.int/foo')
    end

    it 'ignores internal anchor links when finding missing links' do
      deployed = '<main><a href="#section1">Jump</a></main>'
      actual = '<main><p>nothing</p></main>'
      report = auditor.compare(deployed, actual)
      expect(report.missing_links).to be_empty
    end

    it 'detects missing tables' do
      deployed = '<main><table></table><table></table></main>'
      actual = '<main><table></table></main>'
      report = auditor.compare(deployed, actual)
      expect(report.missing_tables).to eq([1])
    end

    it 'falls back to body when main is absent' do
      deployed = '<body><p>alpha bravo</p></body>'
      actual = '<body><p>alpha</p></body>'
      report = auditor.compare(deployed, actual)
      expect(report.coverage).to be < 1.0
    end

    it 'returns a frozen Report' do
      report = auditor.compare('<main></main>', '<main></main>')
      expect(report).to be_frozen
    end

    it 'serializes to a Hash' do
      report = auditor.compare('<main><h2>X</h2><p>foo</p></main>', '<main><h2>X</h2><p>foo</p></main>')
      hash = report.to_report_hash
      expect(hash).to include(:coverage, :sections, :deployed_tokens)
    end
  end
end
