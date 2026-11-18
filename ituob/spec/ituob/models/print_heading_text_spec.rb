# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

# Heading text that the unmapped-line coverage found dropped from the data
# (ituob.github.io#100): E.118, E.164 ACN, E.212 and M.1400 headings.
RSpec.describe 'printed heading text kept as data' do
  describe Ituob::Models::E118Amendment, '.heading_country_beyond' do
    def entry(country, issuer: nil)
      Ituob::Models::E118Entry.new(country_or_area: Ituob::Models::MultilingualString.new(en: country),
                                   issue_id_number: issuer)
    end

    def beyond(heading, entry)
      described_class.heading_country_beyond(heading, entry)
    end

    it 'keeps a former name that the country cell does not carry (issue 960)' do
      expect(beyond('Netherlands (INMO B.V.)', entry('Netherlands'))).to eq('Netherlands (INMO B.V.)')
    end

    it 'keeps a qualifier the country cell lacks (issue 1330)' do
      expect(beyond('Belarus (Rep of.)', entry('Belarus'))).to eq('Belarus (Rep of.)')
    end

    it 'keeps a label-only country (Global Issuer Identifier Number)' do
      expect(beyond('Global Issuer Identifier Number', entry('Global')))
        .to eq('Global Issuer Identifier Number')
    end

    it 'drops a heading that only repeats the country cell (negative control)' do
      expect(beyond('P 49 Netherlands', entry('Netherlands'))).to be_nil
    end

    it 'drops a heading that only repeats the issuer number (negative control)' do
      expect(beyond('89 31', entry('Germany', issuer: '89 31'))).to be_nil
    end

    it 'drops a blank heading (negative control)' do
      expect(beyond('  ', entry('Germany'))).to be_nil
    end
  end

  describe Ituob::Models::E164ACNAmendment, '.heading_caption' do
    def entries(*countries)
      countries.map { |c| Struct.new(:country_or_area).new(Ituob::Models::MultilingualString.new(en: c)) }
    end

    it 'keeps the heading word the table spells differently ("P 9 Georgie LIR *")' do
      expect(described_class.heading_caption('P 9 Georgie LIR *', entries('Georgia'))).to eq('Georgie')
    end

    it 'is nil when the heading only names the entry country (negative control)' do
      expect(described_class.heading_caption('P 9 Georgia LIR *', entries('Georgia'))).to be_nil
    end
  end

  describe Ituob::Models::M1400Amendment do
    def names(text)
      described_class.multilingual_country(text).to_hash.compact
    end

    it 'splits the three printed Liechtenstein names into en/fr/es' do
      expect(names('Liechtenstein (Principality of) / LIELiechtenstein (Principauté de) / LIELiechtenstein (Principalidad de)'))
        .to eq('en' => 'Liechtenstein (Principality of)', 'fr' => 'Liechtenstein (Principauté de)',
               'es' => 'Liechtenstein (Principalidad de)')
    end

    it 'splits the Congo names by wording, not by print order' do
      expect(names('République démocratique du Congo / COD Democratic Republic of the Congo / COD República democratica del Congo'))
        .to eq('en' => 'Democratic Republic of the Congo', 'fr' => 'République démocratique du Congo',
               'es' => 'República democratica del Congo')
    end

    it 'does not leave the French first word glued to the English name (Allemagne Germany)' do
      expect(names("Allemagne Germany (Federal Republic of) / DEU Allemagne (République fédérale d’)"))
        .to eq('en' => 'Germany (Federal Republic of)', 'fr' => "Allemagne (République fédérale d’)")
    end

    it 'keeps a single-language name as en (negative control)' do
      expect(names('Gibraltar')).to eq('en' => 'Gibraltar')
    end

    it 'does not strip an English name that merely starts with the same word as the French one (negative control)' do
      expect(names('Congo (Republic of the) / COG Congo (République du)'))
        .to eq('en' => 'Congo (Republic of the)', 'fr' => 'Congo (République du)')
    end

    describe '.accumulate_country' do
      it 'keeps both printed names for the same ISO' do
        expect(described_class.accumulate_country('Djibouti (Republic of)', 'DJI', 'Djibouti (République de)', 'DJI'))
          .to eq('Djibouti (Republic of) / DJI Djibouti (République de)')
      end

      it 'replaces the name for a different ISO (negative control)' do
        expect(described_class.accumulate_country('Djibouti (Republic of)', 'DJI', 'Gibraltar', 'GIB')).to eq('Gibraltar')
      end

      it 'does not repeat a name already accumulated (negative control)' do
        prev = 'Djibouti (Republic of) / DJI Djibouti (République de)'
        expect(described_class.accumulate_country(prev, 'DJI', 'Djibouti (République de)', 'DJI')).to eq('Djibouti (République de)')
      end
    end

    describe '.heading_with_action' do
      it 'returns the text between the ISO code and the action as caption (Congo "(OCPT)")' do
        res = described_class.heading_with_action('Congo (Republic of the) / COG (OCPT) ADD')
        expect(res[3]).to eq('ADD')
        expect(res[5]).to eq('(OCPT)')
      end

      it 'has no caption when nothing sits between ISO and action (negative control)' do
        expect(described_class.heading_with_action('Congo (Republic of the) / COG ADD')[5]).to be_nil
      end
    end
  end

  describe Ituob::Models::E212MNCAmendment, 'MSIN glossary note' do
    def doc(*texts)
      { 'type' => 'doc', 'content' => texts.map { |t| { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => t }] } } }
    end

    it 'captures the "**MSIN:" trilingual legend as a note' do
      legend = '**MSIN: Mobile subscription identification number / Numéro d’identification de l’abonné mobile'
      notes = described_class.parse(doc('P 35 Rwanda ADD', '635 13 TIGO', legend)).notes
      expect(notes).to include(legend)
    end

    it 'does not capture ordinary text as a note (negative control)' do
      notes = described_class.parse(doc('P 35 Rwanda ADD', '635 13 TIGO', 'Some other sentence')).notes
      expect(notes.to_a).not_to include('Some other sentence')
    end
  end
end
