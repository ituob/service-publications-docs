# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../../../scripts/f32_completeness_check'

RSpec.describe F32CompletenessCheck do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:fixtures) { File.join(root, 'ituob/spec/fixtures/f32') }
  let(:reference) do
    Ituob::Models::F32SeedPublication.from_yaml(File.read(File.join(fixtures, 'completeness/printed.yaml')))
  end
  let(:candidates) do
    Ituob::Support::Yaml.safe_load_file(File.join(fixtures, 'completeness/recovered.yaml')).map do |row|
      Ituob::Models::F32TDIEntry.from_hash(row)
    end
  end
  let(:comparison) do
    Ituob::Models::F32CompletenessChecker.new(
      reference: reference, candidates: candidates, candidate_source: 'two-country recovered rows'
    ).compare
  end

  it 'reports missing, extra and different rows in each country without collapsing shared indicators' do
    expect(comparison.countries.map do |country|
      [country.country, country.matching, country.missing, country.extra, country.different]
    end)
      .to eq([['ALPHA', 2, 1, 1, 0], ['BETA', 1, 0, 0, 1]])
    expect(comparison.missing.map(&:office_code)).to eq(['AAMI'])
    expect(comparison.extra.map(&:office_code)).to eq(['AAEX'])
    expect(comparison.different.map(&:office_code)).to eq(['BBDI'])
    expect(comparison.candidate_rows).to eq(6)
    expect(comparison.candidate_context_rows).to eq(1)

    report = described_class.render(reference: reference, comparison: comparison, candidate_sha256: 'candidate-sha')
    expect(report).to include('| ALPHA | 2 | 1 | 1 | 0', '| BETA | 1 | 0 | 0 | 1')
    expect(report).to include('Matching: 3; missing: 1; extra: 1; different: 1', 'Raw recovered rows: 6',
                              'Recovered context rows: 1')
    expect(report).to include('| Missing | ALPHA | AAMI | Missing |', '| Extra | ALPHA | AAEX |  | Extra |')
    expect(report).to include('| Different | BETA | BBDI | Printed name | Recovered name |')
  end

  it 'reports an assignment captured under a different country as missing and extra' do
    moved = candidates.map { |entry| Ituob::Models::F32TDIEntry.from_yaml(entry.to_yaml) }
    moved.first.country_or_area.fr = 'BETA'
    result = Ituob::Models::F32CompletenessChecker.new(
      reference: reference, candidates: moved, candidate_source: 'wrong-country regression'
    ).compare

    expect(result.matching_keys.length).to eq(2)
    expect(result.missing.map { |difference| [difference.country, difference.office_code] })
      .to include(%w[ALPHA AAMA])
    expect(result.extra.map { |difference| [difference.country, difference.office_code] })
      .to include(%w[BETA AAMA])
  end

  it 'generates a deterministic report from every page of the official print and all raw recovered rows' do
    script = File.join(root, 'scripts/f32_completeness_check.rb')
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, script, '--output', '-')
    expect(status.success?).to be(true), stderr
    expect(stdout).to include('Official printed source: https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-F.32-2011-PDF-E.pdf')
    expect(stdout).to include('7ef59fbbfcddd5690dd4f5e2de87a618e31898c8943ca1335c6c4e2a4556c3d9', 'Source pages: 47',
                              'Raw recovered rows: 1214')
    expect(stdout).to include('Matching: 567; missing: 910; extra: 493; different: 18',
                              'Recovered context rows: 136', 'printed unique allocations: 1092',
                              'printed context rows: 959', '== Country totals',
                              '2afc40eb22639405f917a10e36118e95d263c81cd0d125d7c8f8b907d2154f22')
    expect(stdout.lines.grep(/\A\| Missing \|/).length).to eq(910)
    expect(stdout.lines.grep(/\A\| Extra \|/).length).to eq(493)
    expect(stdout.lines.grep(/\A\| Different \|/).length).to eq(18)
    expect(File.read(File.join(root, 'docs/normalization/f32-completeness-results.adoc'))).to eq(stdout)
    Dir.mktmpdir do |directory|
      output = File.join(directory, 'report.adoc')
      _, error, result = Open3.capture3(RbConfig.ruby, script, '--output', output)
      expect(result.success?).to be(true), error
      expect(File.read(output)).to eq(stdout)
    end
  end

  it 'also compares the original legacy YAML without replaying or collapsing its rows' do
    script = File.join(root, 'scripts/f32_completeness_check.rb')
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, script, '--candidate', File.join(root, 'datasets/980-F.32/data.yaml'), '--output', '-'
    )
    expect(status.success?).to be(true), stderr
    expect(stdout).to include('Raw recovered rows: 816', 'Recovered context rows: 141',
                              'Matching: 656; missing: 821; extra: 1; different: 18',
                              'Candidate source: `datasets/980-F.32/data.yaml`')
  end

  it 'documents the official source and includes the generated completeness results' do
    documentation = File.read(File.join(root, 'docs/normalization/f32-completeness.adoc'))
    expect(documentation).to include('T-SP-F.32-2011-PDF-E.pdf', 'include::f32-completeness-results.adoc[]')
  end
end
