# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe 'Q.708 source boundaries' do
  let(:messages) do
    Ituob::Support::Yaml.load_source_file(
      File.join(FIXTURE_ROOT, issue.to_s, 'amendments.yaml'),
    ).fetch('messages')
  end
  let(:source) do
    messages.find { |message| message.dig('target', 'publication') == publication }
      .fetch('contents').fetch('en')
  end
  let(:parser) { Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS.fetch(publication) }
  let(:amendment) { parser.parse(source) }

  context 'when OB 1221 combines numerical and alphabetical SANC tables' do
    let(:issue) { 1221 }
    let(:publication) { 'Q708_SANC' }

    it 'keeps both Oman listings and the glossary without inventing an allocation' do
      expect(amendment.actions.map(&:order)).to eq(['Numerical order', 'Alphabetical order'])
      expect(amendment.actions.map(&:action_type)).to eq(%w[ADD ADD])
      expect(amendment.actions.flat_map(&:entries).map(&:code)).to eq(%w[4-202 4-202])
      expect(amendment.actions.flat_map(&:entries).map { |entry| entry.area_or_network.en })
        .to eq(['Oman (Sultanate of)', 'Oman (Sultanate of)'])
      expect(amendment.notes.join("\n")).to include(
        'SANC:', 'Signalling Area/Network Code.', 'Code de zone/réseau', 'Código de zona/red',
      )
    end
  end

  context 'when OB 1167 labels an M.1400 contact table as Q.708' do
    let(:issue) { 1167 }
    let(:publication) { 'Q708_ISPC' }

    it 'does not create ISPC actions from the carrier contact table' do
      expect(amendment.actions).to be_empty
    end

    it 'preserves a real ISPC section following a misplaced carrier section' do
      valid_source = Ituob::Support::Yaml.load_source_file(
        File.join(FIXTURE_ROOT, '1335', 'amendments.yaml'),
      ).fetch('messages').find { |message| message.dig('target', 'publication') == 'Q708_ISPC' }
        .fetch('contents').fetch('en')
      mixed_source = source.merge('content' => source.fetch('content') + valid_source.fetch('content'))

      expect(parser.parse(mixed_source).to_yaml).to eq(parser.parse(valid_source).to_yaml)
    end

    it 'preserves the authentic M.1400 suppression' do
      carrier_source = messages.find { |message| message.dig('target', 'publication') == 'M1400_ICC' }
        .fetch('contents').fetch('en')
      carrier_amendment = Ituob::Models::M1400Amendment.parse(carrier_source)
      suppression = carrier_amendment.actions.find { |action| action.action_type == 'SUP' }

      expect(suppression.entries.map(&:carrier_code)).to eq(['CH4141'])
      expect(suppression.entries.first.company_name).to include('Genza SA', 'Rue de Lausanne 37', '1201 GENEVE')
    end
  end
end
