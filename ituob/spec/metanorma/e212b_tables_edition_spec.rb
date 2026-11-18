# frozen_string_literal: true

require 'spec_helper'

# documents/T-SP-E.212B-2018/_tables_edition.liquid renders the main E.212 MNC
# table from a provider edition. The register can hold rows that are not clean
# table rows, so the template has to defend the AsciiDoc table.
RSpec.describe 'T-SP-E.212B-2018/_tables_edition.liquid' do
  let(:template_path) do
    File.expand_path('../../../documents/T-SP-E.212B-2018/_tables_edition.liquid', __dir__)
  end
  let(:template) { Liquid::Template.parse(File.read(template_path)) }

  def entry(code, network, country = {})
    e = Ituob::Models::E212MNCEntry.new
    e.mcc_mnc_codes = code
    e.networks = network
    e.country_or_area = Ituob::Models::MultilingualString.new(**country) unless country.empty?
    e
  end

  def render(*items)
    metadata = Ituob::Provider.new.locale(register: "e212-mnc")
    edition = Ituob::Models::RegisterEdition.new(items: items, metadata: metadata)
    template.render!('edition' => edition)
  end

  # Returns [span, country, network, code] per data row; span and country are
  # nil on rows that continue a rowspan cell.
  def rows(out)
    lines = out.lines.map(&:strip).reject(&:empty?)
    lines = lines.drop(lines.index('^| MCC + MNC codes') + 1)
    span = country = nil
    lines.each_with_object([]) do |line, acc|
      if (m = line.match(/\A\.(\d+)\+\| (.*) \| \|\z/))
        span = m[1]
        country = m[2]
      elsif line.start_with?('^|')
        acc.last << line.delete_prefix('^|').strip
      elsif line.start_with?('|') && line != '|==='
        acc << [span, country, line.delete_prefix('|').strip]
        span = country = nil
      end
    end
  end

  it 'merges a run of the same country into one rowspan cell' do
    out = render(entry('234 01', 'A', en: 'United Kingdom'),
                 entry('234 02', 'B', en: 'United Kingdom'),
                 entry('208 01', 'C', en: 'France'))

    expect(rows(out)).to eq([['3', 'United Kingdom', 'A', '234 01'],
                             [nil, nil, 'B', '234 02'],
                             ['2', 'France', 'C', '208 01']])
  end

  it 'escapes a pipe in the country, network and code cells' do
    out = render(entry('9|9 01', 'Iowa | Wireless', en: 'Cote | d Ivoire'))

    expect(out).to include('| Cote \| d Ivoire | |')
    expect(out).to include('| Iowa \| Wireless')
    expect(out).to include('^| 9\|9 01')
    expect(out).not_to match(/Iowa [^\\]\| Wireless/)
  end

  it 'drops a row whose code and network are blank without breaking the country run' do
    out = render(entry('268 01', 'X', en: 'Portugal'),
                 entry(' ', ' ', en: 'Portugal SUP'),
                 entry('268 03', 'Y', en: 'Portugal'))

    expect(out).not_to include('Portugal SUP')
    expect(rows(out)).to eq([['3', 'Portugal', 'X', '268 01'], [nil, nil, 'Y', '268 03']])
  end

  it 'keeps a row that has a code but no network' do
    expect(rows(render(entry('901 01', ' ', en: 'Intl')))).to eq([['2', 'Intl', '', '901 01']])
  end

  it 'falls back to another language when the English country is missing' do
    out = render(entry('208 01', 'A', fr: 'France'), entry('212 01', 'B', es: 'Mónaco', zh: 'x'))

    expect(rows(out).map { |r| r[1] }).to eq(%w[France Mónaco])
  end

  it 'leaves a country-less row blank and does not merge it into the previous country' do
    out = render(entry('234 01', 'A', en: 'United Kingdom'), entry('208 23', 'B'))

    expect(rows(out)).to eq([['2', 'United Kingdom', 'A', '234 01'], ['2', '', 'B', '208 23']])
  end
end
