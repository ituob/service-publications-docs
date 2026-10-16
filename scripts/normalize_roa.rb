#!/usr/bin/env ruby
# frozen_string_literal: true
# Converts service-publications-data/roa/roa.yaml into the normalized dataset
# shape required by service-publications-docs/datasets/roa/.

require 'yaml'
require 'fileutils'

SRC = '/Users/mulgogi/src/ituob/service-publications-data/roa/roa.yaml'
DST = '/Users/mulgogi/src/ituob/service-publications-docs/datasets/roa'

FileUtils.mkdir_p(DST)

raw = YAML.load_file(SRC, permitted_classes: [Date, Time])
metadata = raw['metadata']
entries = raw['data']

File.write(File.join(DST, 'metadata.yaml'), <<~YAML)
  # yaml-language-server: $schema=../schema-metadata.yaml
  ---
  title:
    en: List of Recognized Operating Agencies (ROAs)
    fr: Liste des exploitations reconnues (ER)
    es: Lista de empresas de explotación reconocidas (EER)
  url: https://www.itu.int/ITU-T/inr/roa/index.html
  source: service-publications-data/roa/roa.yaml
  locale:
    - key: country_or_area
      en: Country or geographic area
      fr: Pays ou zone géographique
      es: País o área geográfica
    - key: company_name
      en: Company's (ROA) name
      fr: Nom de la société (ER)
      es: Nombre de la empresa (EER)
    - key: address
      en: Company's (ROA) address
      fr: Adresse de la société (ER)
      es: Dirección de la empresa (EER)
    - key: tel
      en: Tel
      fr: Tél
      es: Tel
    - key: fax
      en: Fax
      fr: Fax
      es: Fax
    - key: email
      en: E-mail
      fr: E-mail
      es: E-mail
    - key: url
      en: URL
      fr: URL
      es: URL
    - key: ob_issue_number
      en: OB
      fr: OB
      es: OB
YAML

File.write(File.join(DST, 'schema-data.yaml'), <<~YAML)
  # yaml-language-server: $schema=http://json-schema.org/draft-07/schema#
  ---
  $schema: http://json-schema.org/draft-07/schema#
  title: ITU OB Dataset Schema for roa
  description: ITU OB Dataset Schema for the List of Recognized Operating Agencies (ROAs)
  type: array
  items:
    type: object
    required:
      - country_or_area
      - company_name
    properties:
      country_or_area:
        type: string
        description: Country or geographic area where the ROA is registered.
      company_name:
        type: string
        description: The ROA's official company name.
      address:
        type: string
        description: Postal address of the ROA.
      tel:
        type: string
        description: Telephone contact number.
      fax:
        type: string
        description: Fax contact number.
      email:
        type: string
        description: Email contact address.
      url:
        type: string
        description: Public website URL.
      ob_issue_number:
        type: string
        description: The OB issue number in which this ROA was last updated.
    additionalProperties: false
YAML

normalized = entries.map do |e|
  entry = { 'country_or_area' => e['country_or_area'], 'company_name' => e['company_name'] }
  %w[address tel fax email url ob_issue_number].each do |k|
    entry[k] = e[k] if e[k]
  end
  entry
end

yaml_payload = YAML.dump(normalized)
yaml_payload.sub!(/\A---\n/, '')
File.write(File.join(DST, 'data.yaml'), "# yaml-language-server: $schema=schema-data.yaml\n---\n" + yaml_payload)

puts "Wrote #{normalized.size} ROA entries to #{DST}/data.yaml"
