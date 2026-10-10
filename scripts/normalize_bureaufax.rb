#!/usr/bin/env ruby
# frozen_string_literal: true
# Converts service-publications-data/bureaufax/bureaufax.part3.yaml into the
# normalized dataset shape required by service-publications-docs/datasets/bureaufax/.
#
# Output:
#   datasets/bureaufax/metadata.yaml
#   datasets/bureaufax/schema-data.yaml
#   datasets/bureaufax/data.yaml

require 'yaml'
require 'fileutils'

SRC = '/Users/mulgogi/src/ituob/service-publications-data/bureaufax/bureaufax.part3.yaml'
DST = '/Users/mulgogi/src/ituob/service-publications-docs/datasets/bureaufax'

FileUtils.mkdir_p(DST)

raw = YAML.load_file(SRC, permitted_classes: [Date, Time])
metadata = raw['metadata']
entries = raw['data']

# metadata.yaml
File.write(File.join(DST, 'metadata.yaml'), <<~YAML)
  # yaml-language-server: $schema=../schema-metadata.yaml
  ---
  title:
    en: Bureaufax Table
    fr: Tableau Bureaufax
    es: Tabla Bureaufax
  recommendation:
    body: ITU-T
    code: F.170
  url: https://www.itu.int/ITU-T/inr/bureaufax/index.html
  source: service-publications-data/bureaufax/bureaufax.part3.yaml
  locale:
    - key: country_or_area
      en: Country or geographical area
      fr: Pays ou zone géographique
      es: País o zona geográfica
    - key: location
      en: Location
      fr: Emplacement
      es: Emplazamiento
    - key: access_code
      en: Access code (Part III 1a)
      fr: Code d'accès (Partie III 1a)
      es: Código de acceso (Parte III 1a)
    - key: bureaufax_number
      en: Bureaufax number (Part III 2)
      fr: Numéro Bureaufax (Partie III 2)
      es: Número Bureaufax (Parte III 2)
    - key: destination_priority
      en: Destination priority (Part III 3)
      fr: Priorité de destination (Partie III 3)
      es: Prioridad de destino (Parte III 3)
    - key: availability
      en: Availability (Part III 4)
      fr: Disponibilité (Partie III 4)
      es: Disponibilidad (Parte III 4)
    - key: monday
      en: Monday
      fr: Lundi
      es: Lunes
    - key: tuesday
      en: Tuesday
      fr: Mardi
      es: Martes
    - key: wednesday
      en: Wednesday
      fr: Mercredi
      es: Miércoles
    - key: thursday
      en: Thursday
      fr: Jeudi
      es: Jueves
    - key: friday
      en: Friday
      fr: Vendredi
      es: Viernes
    - key: saturday
      en: Saturday
      fr: Samedi
      es: Sábado
    - key: sunday
      en: Sunday
      fr: Dimanche
      es: Domingo
    - key: public_holidays
      en: Public holidays
      fr: Jours fériés
      es: Días festivos
YAML

# schema-data.yaml
File.write(File.join(DST, 'schema-data.yaml'), <<~YAML)
  # yaml-language-server: $schema=http://json-schema.org/draft-07/schema#
  ---
  $schema: http://json-schema.org/draft-07/schema#
  title: ITU OB Dataset Schema for bureaufax
  description: ITU OB Dataset Schema for bureaufax (Recommendation ITU-T F.170)
  type: array
  items:
    type: object
    required:
      - country_or_area
      - location
    properties:
      country_or_area:
        type: string
        description: Country or geographical area where the bureaufax bureau is located.
      access_code:
        type: string
        description: The bureaufax access code (Part III 1a) if assigned.
      location:
        type: string
        description: City or location of the bureaufax bureau (Part III 1b).
      bureaufax_number:
        type: string
        description: The bureaufax number (Part III 2).
      destination_priority:
        type: string
        description: The destination priority code (Part III 3).
      availability:
        type: object
        description: Service availability windows (Part III 4).
        properties:
          monday_friday:
            type: string
          saturday:
            type: string
          sunday_public_holidays:
            type: string
      hours:
        type: object
        properties:
          monday:
            type: string
          tuesday:
            type: string
          wednesday:
            type: string
          thursday:
            type: string
          friday:
            type: string
          saturday:
            type: string
          sunday:
            type: string
          public_holidays:
            type: string
    additionalProperties: false
YAML

# data.yaml: convert each raw entry into the normalized shape.
normalized = entries.map do |e|
  entry = {
    'country_or_area' => e['name'],
    'location' => e['part31b_location'],
  }
  entry['access_code'] = e['part31a'] if e['part31a']
  entry['bureaufax_number'] = e['part32'] if e['part32']
  entry['destination_priority'] = e['part33'] if e['part33']
  if e['part34a_mon_fri'] || e['part34a_sat'] || e['part34a_sun_pub']
    entry['availability'] = {}
    entry['availability']['monday_friday'] = e['part34a_mon_fri'] if e['part34a_mon_fri']
    entry['availability']['saturday'] = e['part34a_sat'] if e['part34a_sat']
    entry['availability']['sunday_public_holidays'] = e['part34a_sun_pub'] if e['part34a_sun_pub']
  end
  hours_keys = %w[monday tuesday wednesday thursday friday saturday sunday public_holidays]
  hours = {}
  hours_keys.each do |k|
    hours[k] = e[k] if e[k]
  end
  entry['hours'] = hours unless hours.empty?
  entry
end

yaml_payload = YAML.dump(normalized)
yaml_payload.sub!(/\A---\n/, '')
File.write(File.join(DST, 'data.yaml'), "# yaml-language-server: $schema=schema-data.yaml\n---\n" + yaml_payload)

puts "Wrote #{normalized.size} bureaufax entries to #{DST}/data.yaml"
