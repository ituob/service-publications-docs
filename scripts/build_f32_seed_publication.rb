# frozen_string_literal: true

require "fileutils"
require_relative "../ituob/lib/ituob/models"

root = File.expand_path("..", __dir__)
seed_path = File.join(root, "datasets/980-F.32/data.yaml")
fixture_dir = File.join(root, "ituob/spec/fixtures/f32")
output_path = File.join(root, "datasets/980-F.32/publication.yaml")

publication = Ituob::Models::F32SeedBuilder.new(seed_path: seed_path).build_complete(
  xml_path: File.join(fixture_dir, "official-2011.xml"),
  pdf_path: File.join(fixture_dir, "official-2011.pdf"),
)
raise "The printed F.32 publication was not independently parsed completely" unless publication.source_complete

File.write(output_path, publication.to_yaml)
reloaded = Ituob::Models::F32SeedPublication.from_yaml(File.read(output_path))
unless reloaded.source_complete && reloaded.source_sha256 == publication.source_sha256 &&
    reloaded.allocations.map(&:office_code) == publication.allocations.map(&:office_code)
  raise "The generated F.32 publication did not round-trip through its LML model"
end

puts "Wrote #{output_path}"
puts "Source SHA-256: #{reloaded.source_sha256}"
puts "Pages: #{reloaded.pages.length}; allocations: #{reloaded.allocations.length}; contexts: #{reloaded.contexts.length}"
