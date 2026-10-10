# frozen_string_literal: true

require 'spec_helper'
require 'ituob/parity'

RSpec.describe Ituob::Parity::UrlMap do
  describe '.map' do
    context 'with issue URLs' do
      it 'maps /issues/1234-en/ to /issues/1234/' do
        expect(described_class.map('/issues/1234-en/')).to eq('/issues/1234/')
      end

      it 'maps /issues/1234-en (no trailing slash)' do
        expect(described_class.map('/issues/1234-en')).to eq('/issues/1234/')
      end

      it 'maps language variants to the canonical issue page' do
        expect(described_class.map('/issues/1234-fr')).to eq('/issues/1234/')
        expect(described_class.map('/issues/1234-zh')).to eq('/issues/1234/')
        expect(described_class.map('/issues/1234-ru')).to eq('/issues/1234/')
      end

      it 'preserves anchor when present' do
        expect(described_class.map('/issues/1234-en/#amendments-1'))
          .to eq('/issues/1234/#amendments-1')
      end
    end

    context 'with year-numeric relative paths' do
      it 'drops 4-digit years (year navigation)' do
        expect(described_class.map('../2018/')).to be_nil
        expect(described_class.map('2018/')).to be_nil
      end

      it 'maps non-year numeric paths to issue URLs' do
        expect(described_class.map('../1234/')).to eq('/issues/1234/')
        expect(described_class.map('1234/')).to eq('/issues/1234/')
      end
    end

    context 'with recommendation URLs (containing literal spaces)' do
      it 'maps /messages/complement-to-itu-t-r E.118/ to /recommendations/E.118/' do
        expect(described_class.map('/messages/complement-to-itu-t-r E.118/'))
          .to eq('/recommendations/E.118/')
      end

      it 'handles URLs without trailing slash' do
        expect(described_class.map('/messages/complement-to-itu-t-r E.118'))
          .to eq('/recommendations/E.118/')
      end
    end

    context 'with amending-sp register URLs' do
      it 'maps /messages/amending-sp E212_MNC (date)/ to /registers/e212-mnc/' do
        expect(described_class.map('/messages/amending-sp E212_MNC (2018-12-15 00:00:00 UTC)/'))
          .to eq('/registers/e212-mnc/')
      end

      it 'maps amending-sp without date to the slug' do
        expect(described_class.map('/messages/amending-sp BUREAUFAX (-)/'))
          .to eq('/registers/bureaufax/')
      end

      it 'returns nil for unknown register IDs' do
        expect(described_class.map('/messages/amending-sp UNKNOWN (-)/')).to be_nil
      end
    end

    context 'with intentionally-dropped URLs' do
      it 'drops /_app_help/' do
        expect(described_class.map('/_app_help/')).to be_nil
        expect(described_class.map('/_app_help/amend-publication/')).to be_nil
      end

      it 'drops /assets/' do
        expect(described_class.map('/assets/css/style.css')).to be_nil
      end

      it 'drops external URLs' do
        expect(described_class.map('https://www.itu.int/pub/T-SP-OB.1234-1')).to be_nil
        expect(described_class.map('http://example.com')).to be_nil
      end

      it 'drops mailto: URLs' do
        expect(described_class.map('mailto:foo@bar.com')).to be_nil
      end

      it 'drops anchor-only URLs' do
        expect(described_class.map('#section-1')).to be_nil
      end
    end

    context 'with whitespace handling' do
      it 'strips leading/trailing whitespace' do
        expect(described_class.map('  /issues/1234-en/  '))
          .to eq('/issues/1234/')
      end

      it 'collapses internal newlines but preserves internal spaces' do
        wrapped = "\n  /messages/complement-to-itu-t-r\n  E.118/\n"
        expect(described_class.map(wrapped)).to eq('/recommendations/E.118/')
      end

      it 'returns nil for nil input' do
        expect(described_class.map(nil)).to be_nil
      end

      it 'returns nil for empty string' do
        expect(described_class.map('')).to be_nil
        expect(described_class.map('   ')).to be_nil
      end
    end

    context 'with unknown URLs' do
      it 'returns the URL unchanged for unmapped paths' do
        expect(described_class.map('/unknown/path/')).to eq('/unknown/path/')
      end

      it 'maps / to /' do
        expect(described_class.map('/')).to eq('/')
      end
    end

    context 'with /messages/running_annexes/' do
      it 'maps to /types/running_annexes/' do
        expect(described_class.map('/messages/running_annexes/'))
          .to eq('/types/running_annexes/')
      end
    end
  end
end
