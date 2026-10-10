#!/usr/bin/env ruby
# frozen_string_literal: true
# generate_sources_manifest.rb
#
# Builds service-publications-data/SOURCES.yaml — an index of every file under
# service-publications-data/, mapping each to the dataset it belongs to and the
# date the snapshot represents.

require 'yaml'
require 'fileutils'

DATA_ROOT = ENV.fetch('SERVICE_PUB_DATA_ROOT',
                      File.expand_path('../service-publications-data', __dir__))

# Map dataset-by-prefix directory under service-publications-data/ to the
# corresponding service-publications-docs/datasets/{name}/ slug.
DATASET_PREFIX_TO_SLUG = {
  '1000-SR.1' => '1000-SR.1',
  '1001-T.35B' => '1001-T.35B',
  '1002-T.35' => '1002-T.35',
  '1015-E.164B' => '1015-E.164B',
  '1060-M.1400' => '1060-M.1400',
  '1109-Q.708B' => '1109-Q.708B',
  '1114-E.164D' => '1114-E.164D',
  '1117-E.212A' => '1117-E.212A',
  '1125-E.218' => '1125-E.218',
  '1125-Q.708A' => '1125-Q.708A',
  '1154-RR.25.1' => '1154-RR.25.1',
  '1161-E.118' => '1161-E.118',
  '1162-E.212' => '1162-E.212',
  '669-F.1' => '669-F.1',
  '955-E.180' => '955-E.180',
  '974-F.400' => '974-F.400',
  '976-X.121A' => '976-X.121A',
  '977-X.121B' => '977-X.121B',
  '978-F.68' => '978-F.68',
  '980-F.32' => '980-F.32',
  '991-PP.RES.21.pp' => '991-PP.RES.21.pp',
  '994-E.164C' => '994-E.164C',
  'bureaufax' => 'bureaufax',
  'icc' => 'icc',  # alias of 1060-M.1400
  'roa' => 'roa',
  'country_codes' => 'iso-3166',
  'scripts' => nil, # not a dataset
}

entries = []

Dir.children(DATA_ROOT).sort.each do |top|
  next if top.start_with?('.')
  next if top == 'archived-data'
  top_path = File.join(DATA_ROOT, top)
  unless File.directory?(top_path)
    entries << { 'path' => top, 'dataset' => nil, 'as_of' => nil,
                 'notes' => 'top-level non-directory file' }
    next
  end

  dataset = DATASET_PREFIX_TO_SLUG[top]

  Dir.glob(File.join(top_path, '**/*')).each do |f|
    next unless File.file?(f)
    rel = f.sub("#{DATA_ROOT}/", '')
    ext = File.extname(f).downcase
    as_of = case ext
            when '.yaml', '.csv', '.xlsx'
              # Try to extract a date from the filename or use file mtime.
              m = File.basename(f).match(/(\d{4})-?(\d{2})-?(\d{2})/)
              m ? "#{m[1]}-#{m[2]}-#{m[3]}" : File.mtime(f).utc.iso8601[0, 10]
            else
              File.mtime(f).utc.iso8601[0, 10]
            end
    entries << {
      'path' => rel,
      'dataset' => dataset,
      'as_of' => as_of,
      'format' => ext.sub(/^\./, ''),
    }
  end
end

manifest = {
  'generated_at' => Time.now.utc.iso8601,
  'data_root' => DATA_ROOT,
  'file_count' => entries.size,
  'files' => entries,
}

OUT = File.join(DATA_ROOT, 'SOURCES.yaml')
payload = YAML.dump(manifest)
payload.sub!(/\A---\n/, '')
File.write(OUT, payload)
puts "Wrote #{OUT} (#{entries.size} entries)"
