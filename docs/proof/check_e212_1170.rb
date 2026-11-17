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
require "json"
require "nokogiri"
require "open3"
require "tmpdir"
require "fileutils"
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

# The plugin's own discovery (Gem.find_files) loads the ituob gem's
# registration file; no local registration here.
Metanorma::Plugin::Lutaml::DataProviders.fetch("ituob")

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
      rows.map { |r| r[1] } == items.map { |i| i.mcc_mnc_codes.to_s.strip.gsub(/\s+/, " ") }
check "rendered first #{FIRST_N} rows == pinned replay order",
      rows.first(FIRST_N).map { |r| r[1] } == PINNED_FIRST, rows.first(FIRST_N).map { |r| r[1] }.inspect

# --- Site parity ------------------------------------------------------------
# Snapshot the site reads, generated from the same checkout.
REPO_ROOT = File.expand_path("../..", __dir__)
snap_dir = Dir.mktmpdir("e212-snap")
snap_out, = Open3.capture2e(
  { "SNAPSHOTS_OUT" => snap_dir }, RbConfig.ruby, "-rliquid", "-rituob",
  File.join(REPO_ROOT, "scripts", "generate_register_snapshots.rb"), "E212_MNC"
)
check "site snapshot generated (scripts/generate_register_snapshots.rb E212_MNC)",
      # the script's exit status also reflects other registers' missing manifests
      snap_out.include?(", 0 errors") && File.exist?(File.join(snap_dir, REGISTER, "at-#{AS_OF}.json")),
      snap_out.lines.last.to_s.strip
snap = JSON.parse(File.read(File.join(snap_dir, REGISTER, "at-#{AS_OF}.json")))
site_rows = snap.fetch("active_entries")

# Same cell text as the site's formatCellValue (RegisterTable.astro): strings
# as is, multilingual values as every populated language in fr en es zh ru ar order.
LANGS = %w[fr en es zh ru ar].freeze
def site_cell(value)
  value = value.values_at(*LANGS).compact.reject(&:empty?).join(" ") if value.is_a?(Hash)
  fold(value.to_s)
end

# standoc's smart-quote / dash typography is applied to the converted XML, so
# both sides are folded to plain quotes and " - " before the comparison. Letters,
# digits and every other character must still match exactly.
def fold(text)
  text.tr("\u201C\u201D", '""').tr("\u2018\u2019", "''")
      .gsub(/[[:space:]]*[\u2014\u2013][[:space:]]*|[[:space:]]+-[[:space:]]+/, " - ")
      .strip.gsub(/[[:space:]]+/, " ")
end
# RegisterTable shows the sorted union of field keys; the proof table has the same columns.
SITE_COLUMNS = %w[country_or_area mcc_mnc_codes networks note].freeze
check "site snapshot columns == proof table columns",
      site_rows.flat_map(&:keys).uniq.sort == SITE_COLUMNS, site_rows.flat_map(&:keys).uniq.sort.inspect
header = doc.xpath("//table//thead//th | //table//tr[1]/th").map { |th| th.text.strip }
check "proof table header == site columns", header == SITE_COLUMNS.map { |c| c.tr("_", " ") }, header.inspect

check "site snapshot at_ob_issue and entry_count",
      snap["at_ob_issue"] == AS_OF && snap["entry_count"] == site_rows.size,
      "at #{snap['at_ob_issue']}, entry_count #{snap['entry_count']}, active #{site_rows.size}"
site_line = "State as of OB No. #{snap['at_ob_issue']} \u00B7 #{snap['entry_count']} active entries"
check "output provenance line == site line #{site_line.inspect}",
      text.lines.map(&:strip).include?(site_line), text[/State as of[^\n]*/].inspect

check "rendered row count == site snapshot active entries", rows.size == site_rows.size,
      "rendered #{rows.size}, site #{site_rows.size}"
check "rendered keys and order == site snapshot (all rows)",
      rows.map { |r| fold(r[1]) } == site_rows.map { |r| site_cell(r["mcc_mnc_codes"]) }
mismatch = rows.zip(site_rows).each_with_index.reject do |(r, s), _i|
  s && r.map { |c| fold(c) } == SITE_COLUMNS.map { |c| site_cell(s[c]) }
end
check "every rendered cell (country or area, mcc mnc codes, networks, note) == site snapshot",
      mismatch.empty?,
      mismatch.first(3).map { |(r, s), i| "row #{i} #{s['mcc_mnc_codes'].inspect}: #{r.inspect}" }.join(" | ")
check "provider items == site snapshot keys in order",
      items.map { |i| i.mcc_mnc_codes.to_s } == site_rows.map { |r| r["mcc_mnc_codes"].to_s }
FileUtils.rm_rf(snap_dir)

puts "output: #{OUT}"
if $failures.empty?
  puts "RESULT PASS: #{rows.size} rows, as_of_issue #{prov.as_of_issue}, " \
       "register #{prov.register_id}, seed_issue #{prov.seed_issue}"
else
  puts "RESULT FAIL: #{$failures.size} check(s) failed: #{$failures.join('; ')}"
  exit 1
end
