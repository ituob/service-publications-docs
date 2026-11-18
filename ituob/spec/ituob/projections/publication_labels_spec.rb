# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Projections::PublicationLabels do
  let(:provider) { Ituob::Provider.new }

  {
    '976-X.121A' => ['country_or_area', { 'en' => 'Country or geographical area', 'fr' => 'Pays ou zone géographique', 'es' => 'País o zona geográfica' }],
    '1000-SR.1' => ['geographic_area', { 'en' => 'Country/geographical area', 'fr' => 'Pays/Zones géographiques', 'es' => 'Países/Zonas geográficas' }],
    '1162-E.212-MCC-Others' => ['mcc_mnc_codes', { 'en' => 'MCC + MNC codes', 'fr' => 'Codes MCC + MNC', 'es' => 'Indicativos MCC + MNC', 'ar' => 'الرموز MCC + MNC', 'ru' => 'Коды MCC + MNC', 'zh' => 'MCC + MNC代码' }],
    '1154-RR.25.1' => ['rr251_administration', { 'en' => 'Administration of the country or geographical area', 'fr' => 'Administration du pays ou zone géographique', 'es' => 'Administración del país o zona geográfica' }],
    '1001-T.35B' => ['t35b_admin', { 'en' => 'Name of Administration:', 'fr' => 'Nom de l’Administration:', 'es' => 'Nombre de la administración:' }]
  }.each do |dataset, (key, translations)|
    translations.each do |language, label|
      it "serves the #{dataset} #{language} column label through the typed provider" do
        publication = provider.publication(dataset: dataset, as_of: dataset.to_i)
        template = Liquid::Template.parse('{{ edition.metadata.locale | where: "key", key | map: language | first }}')

        expect(template.render!('edition' => publication.to_liquid, 'key' => key, 'language' => language)).to eq(label)
      end
    end
  end
end
