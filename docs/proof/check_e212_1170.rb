# frozen_string_literal: true

# Card 128/129 proof: render the E.212 register as of OB issue 1170 through
# Metanorma (standoc) -> metanorma-plugin-lutaml `lutaml_data` -> the real
# Ituob::Provider facade -> Ituob::Models::RegisterEdition, then assert row
# count, row order and provenance in the converted output.
#
#   cd docs/proof && bundle install && bundle exec ruby check_e212_1170.rb
#
# EXPECTED_COUNT overrides the pinned count (used for the negative control).

require "liquid" # must load before the ituob models
require "nokogiri"
require "metanorma-standoc"
require "metanorma/plugin/lutaml"
require "ituob"

REGISTER = "e212-mnc"
AS_OF = 1170
PINNED_COUNT = 1987        # active entries at issue 1170 from the real replay
PINNED_FIRST = ["412 01", "412 20", "412 40", "412 50", "412 80"].freeze
FIRST_N = PINNED_FIRST.size

ADOC = File.expand_path("e212-1170.adoc", __dir__)
OUT = ENV.fetch("PROOF_OUT", File.join(Dir.tmpdir, "e212-1170.xml"))

$failures = []
def check(label, ok, detail = nil)
  puts "#{ok ? 'PASS' : 'FAIL'} #{label}#{" (#{detail})" if detail}"
  $failures << label unless ok
end

begin
  # fetch runs the plugin's own discovery (Gem.find_files) first.
  Metanorma::Plugin::Lutaml::DataProviders.fetch("ituob")
rescue Metanorma::Plugin::Lutaml::DataProviders::Error
  require_relative "ituob_provider_shim"
  puts "NOTE using docs/proof/ituob_provider_shim.rb (card 127 registration not present)"
end

# Ground truth straight from the provider (not through the document).
edition = Ituob::Provider.new.edition(register: REGISTER, as_of: AS_OF)
prov = edition.provenance
items = edition.items
expected_count = Integer(ENV.fetch("EXPECTED_COUNT", PINNED_COUNT))
catalog = Ituob::Catalogs::Registers.find_by_slug(REGISTER)

puts "provider: #{items.size} items, provenance register_id=#{prov.register_id} " \
     "as_of_issue=#{prov.as_of_issue} seed_issue=#{prov.seed_issue}"
check "edition is the compiled LML Ituob::Models::RegisterEdition",
      edition.instance_of?(Ituob::Models::RegisterEdition)
check "items are the compiled LML Ituob::Models::E212MNCEntry",
      items.all? { |i| i.instance_of?(Ituob::Models::E212MNCEntry) }
check "provider count == pinned #{expected_count}", items.size == expected_count, "got #{items.size}"
check "provider provenance", prov.register_id == catalog.register_id &&
                              prov.as_of_issue == AS_OF && prov.seed_issue == catalog.seed_issue
check "provider first rows are the replay order #{PINNED_FIRST.inspect}",
      items.first(FIRST_N).map(&:mcc_mnc_codes) == PINNED_FIRST,
      items.first(FIRST_N).map(&:mcc_mnc_codes).inspect

# Convert the document.
xml = Asciidoctor.convert(File.read(ADOC), backend: :standoc, safe: :safe,
                                          standalone: true, base_dir: __dir__)
File.write(OUT, xml)
doc = Nokogiri::XML(xml)
doc.remove_namespaces!
text = doc.xpath("//sections//p | //preface//p").map { |p| p.text.strip }.join("\n")

check "output provenance line (register_id, as_of_issue, seed_issue)",
      text.include?("PROVENANCE register_id=#{prov.register_id} as_of_issue=#{AS_OF} " \
                    "seed_issue=#{prov.seed_issue}"),
      text[/PROVENANCE[^\n]*/].inspect
check "output ROWS count line", text.include?("ROWS #{items.size}"), text[/ROWS[^\n]*/].inspect

rows = doc.xpath("//table//tbody/tr").map { |tr| tr.xpath("td").map { |td| td.text.strip.gsub(/\s+/, " ") } }
check "rendered row count == provider items.size", rows.size == items.size,
      "rendered #{rows.size}, provider #{items.size}"
check "rendered row count == asserted #{expected_count}", rows.size == expected_count,
      "rendered #{rows.size}"
check "rendered MCC+MNC column == provider replay order (all rows)",
      rows.map(&:first) == items.map { |i| i.mcc_mnc_codes.to_s.strip.gsub(/\s+/, " ") }
check "rendered first #{FIRST_N} rows == pinned replay order",
      rows.first(FIRST_N).map(&:first) == PINNED_FIRST, rows.first(FIRST_N).map(&:first).inspect
net_ok = rows.zip(items).first(50).all? { |r, i| r[1] == i.networks.to_s.strip.gsub(/\s+/, " ") }
check "rendered Network column matches provider for first 50 rows", net_ok

puts "output: #{OUT}"
if $failures.empty?
  puts "RESULT PASS: #{rows.size} rows, as_of_issue #{prov.as_of_issue}, " \
       "register #{prov.register_id}, seed_issue #{prov.seed_issue}"
else
  puts "RESULT FAIL: #{$failures.size} check(s) failed: #{$failures.join('; ')}"
  exit 1
end
