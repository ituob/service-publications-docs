# frozen_string_literal: true

require 'spec_helper'
require 'set'
require_relative '../../../scripts/ob_print_to_patch_coverage'

RSpec.describe PrintToPatchCoverage::Classifier do
  let(:empty_index) { double('patch index', for_issue: {}) }
  let(:tok) { PrintToPatchCoverage::Tok }
  let(:classify) do
    lambda do |text|
      line = PrintToPatchCoverage::Line.new(
        issue: 1203, slug: 'e212-mnc', text: text,
        tokens: Set.new(tok.with_unpadded(tok.of_print(text)))
      )
      described_class.new(empty_index).classify(line, collision: false)
    end
  end

  [
    'MNC : Mobile Network Code / Code de réseau mobile / Indicativo de red para el servicio móvil',
    '____________ * MCC: Mobile Country Code / Indicatif de pays du mobile / Indicativo de país para el servicio móvil MNC: Mobile Network Code / Code de réseau mobile / Indicativo de red para el servicio móvil',
    '* See page 6 of the present Operational Bulletin No. 1161 of 1.XII.2018.',
    '* See the present ITU Operational Bulletin No 1232 of 15.XI.2021, page 5.',
    'See the present Operational Bulletin No. 1236 of 15.I.2022, page 4.'
  ].each do |text|
    it "preserves corpus exclusion shape: #{text[0, 45]}" do
      expect(classify.call(text).status).to eq(:excluded), text
    end
  end

  [
    'See page 5 of the present Operational Bulletin No. 1203 of 1.IX.2020. MCC+MNC 240 99 is assigned to Example Telecom.',
    'MNC: Mobile Network Code / Code de reseau mobile / Indicativo de red para el servicio movil; MCC+MNC 240 99 is assigned to Example Telecom.',
    'MNC: Mobile Network Code / Code de réseau mobile / Indicativo de red para el servicio móvil This legend explains the code.',
    'See the present ITU Operational Bulletin No. 1232 of 15.XI.2021, page 5. MCC+MNC 240 99 assigned.'
  ].each do |text|
    it "leaves appended content visible: #{text[0, 45]}" do
      result = classify.call(text)
      expect(result.status).to eq(:unmapped), text
      expect(result.missing).not_to be_empty
    end
  end
  [
    '1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |',
    '| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9',
    '1 | 2 | 3',
    'Applicant / Network | Terrestrial trunk radio Mobile Country Code ((T)MCC)* and Terrestrial trunk radio Mobile Network Code ((T)MNC)** | Date of assignment'
  ].each do |text|
    it "excludes complete column guide: #{text[0, 45]}" do
      result = classify.call(text)
      expect(result.status).to eq(:excluded)
      expect(result.detail).to eq('fixed_column_guide')
    end
  end

  [
    '1 | 2 | 4',
    '1 | 2 | 3 | Example Telecom',
    'Applicant / Network | Example Telecom | Date of assignment',
    'Applicant / Network | Terrestrial trunk radio Mobile Country Code ((T)MCC)* and Terrestrial trunk radio Mobile Network Code ((T)MNC)** | Date of assignment | 2025'
  ].each do |text|
    it "preserves content beside column labels: #{text[0, 45]}" do
      expect(classify.call(text).status).to eq(:unmapped)
    end
  end

end
