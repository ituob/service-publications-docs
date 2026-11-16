# frozen_string_literal: true

require "spec_helper"
require "ituob/models"

RSpec.describe Ituob::Models::F32SeedBuilder do
  let(:seed_path) { File.expand_path("../../../../datasets/980-F.32/data.yaml", __dir__) }
  let(:publication) { described_class.new(seed_path: seed_path).build }
  let(:contexts) { publication.contexts }

  it "preserves reserved and telex network records outside office allocations" do
    antigua = contexts.find { |context| context.entry.country_or_area.en == "ANTIGUA AND BARBUDA" }
    expect(antigua.kind).to eq("reservation")
    expect(antigua.entry.network_code).to eq("AK- -")
    expect(antigua.entry.network_code_note.en).to include("remains reserved")
    diego = contexts.find { |context| context.entry.country_or_area.en == "DIEGO GARCÍA" }
    expect(diego.kind).to eq("telex")
    expect(diego.entry.telegraph_office_name.en).to eq("Diego García")
    expect(publication.allocations.map(&:office_code)).to all(match(/\S/))
  end

  it "joins only source-proved wrapped office names and retains the original fragments" do
    office = publication.allocations.find { |entry| entry.office_code == "BNDP" }
    expect(office.telegraph_office_name.en).to eq("Manama Diplomatic Area Counter")
    continuation = contexts.find { |context| context.related_office_code == "BNDP" }
    expect(continuation.entry.telegraph_office_name.en).to eq("Manama Diplomatic")
    expect(continuation.continuation_target.telegraph_office_name.en).to eq("Area Counter")
    expect(continuation.source_page).to eq(5)
    expect(continuation.source_row).to be_positive
    belgium = publication.allocations.find { |entry| entry.office_code == "BEOS" }
    expect(belgium.telegraph_office_name.en).to eq("Oostende Radio / Ostende Radio")
  end

  it "retains aliases and the unassigned printed Russian office without inventing a key" do
    alias_record = contexts.find { |context| context.entry.telegraph_office_name&.en == "Dacca --> Dhaka" }
    expect(alias_record.kind).to eq("alias")
    russian = contexts.find { |context| context.entry.country_or_area.en == "RUSSIAN FEDERATION" && context.kind == "printed-unassigned" }
    expect(russian.entry.telegraph_office_name.en).to eq("All others")
    expect(russian.entry.office_code).to be_nil
    expect(russian.source_page).to eq(15)
    expect(publication.allocations.map(&:office_code)).not_to include("RUXX")
  end

  it "keeps allocation identities unique and retains every original source record" do
    keys = publication.allocations.map do |entry|
      Ituob::Registers::Strategies::Base.entry_key(entry.to_hash, "office_code")
    end
    expect(keys.uniq).to eq(keys)
    original = Ituob::Support::Yaml.safe_load_file(seed_path).map do |row|
      Ituob::Models::F32TDIEntry.from_hash(row).to_yaml
    end
    retained = publication.legacy_rows.map(&:to_yaml) + publication.allocations.map(&:to_yaml) + contexts.flat_map do |context|
      [context.entry, context.continuation_target].compact.map(&:to_yaml)
    end
    expect(original - retained).to be_empty
  end

  it "roundtrips allocations, all typed contexts and provenance through compiled-model YAML" do
    restored = Ituob::Models::F32SeedPublication.from_yaml(publication.to_yaml)
    expect(restored.allocations.map(&:to_yaml)).to eq(publication.allocations.map(&:to_yaml))
    expect(restored.contexts.map(&:to_yaml)).to eq(contexts.map(&:to_yaml))
    expect(restored.seed_sha256).to eq(Digest::SHA256.file(seed_path).hexdigest)
    expect(restored.source_path).to eq("datasets/980-F.32/data.yaml")
    expect(restored.source_row_count).to eq(publication.allocations.length + contexts.length)
    expect(restored.source_complete).to be false
  end

  it "preserves legacy multilingual annotations on allocations matched to the official print" do
    fixtures = File.expand_path("../../fixtures/f32", __dir__)
    complete = described_class.new(seed_path: seed_path).build_complete(
      xml_path: File.join(fixtures, "official-2011.xml"), pdf_path: File.join(fixtures, "official-2011.pdf")
    )
    legacy = complete.legacy_rows.find do |entry|
      entry.network_roa_note && entry.office_code.to_s.match?(/\A[A-Z]{4}\z/)
    end
    printed = complete.allocations.find { |entry| entry.office_code == legacy.office_code }

    expect(printed).not_to be_nil
    expect(printed.network_roa_note.to_hash).to include(legacy.network_roa_note.to_hash)
  end
  describe "printed offices whose code sits in the name cell" do
    let(:complete) do
      fixtures = File.expand_path("../../fixtures/f32", __dir__)
      described_class.new(seed_path: seed_path).build_complete(
        xml_path: File.join(fixtures, "official-2011.xml"), pdf_path: File.join(fixtures, "official-2011.pdf")
      )
    end
    let(:allocations) { complete.allocations.to_h { |entry| [entry.office_code, entry.telegraph_office_name.en] } }
    let(:relative) do
      complete.contexts.select { |context| context.kind == "network-relative-office" }
              .to_h { |context| [[context.related_office_code, context.entry.telegraph_office_name.en], context] }
    end

    it "keeps single-network offices as separate allocations and never glues a code into the next name" do
      expect(allocations).to include("PHBG" => "Baguio", "PHBT" => "Butuan City Agusan Del Norte",
                                     "PHCB" => "Cebu", "YNSA" => "Sanaa", "YNTZ" => "Taiz / Tayz")
      expect(allocations.values.grep(/--[A-Z]{2}/)).to be_empty
      expect(complete.legacy_rows.map { |entry| entry.office_code.to_s }).not_to include("PHBG")
    end

    it "retains multi-network offices as their own contexts, not as part of the next name" do
      expect(relative.keys).to include(["--AR", "Arica"], ["--CA", "Calama"], ["--CH", "Chillán"],
                                       ["--CO", "Curico"], ["--IQ", "Iquique"], ["--LS", "La Serena"],
                                       ["--OV", "Ovalle"], ["--TL", "Talca"], ["--OO", "Porto"],
                                       ["--JJ", "33052 CERVIGNANO DEL FRIULI"], ["--NX", "All others"])
      names = complete.contexts.map { |context| context.entry.telegraph_office_name&.en.to_s }
      expect(names.grep(/--[A-Z]{2}/).reject { |name| name.include?("-->") }).to be_empty
    end

    it "accounts for every printed office row" do
      expect(complete.allocations.length).to eq(956)
    end
  end
end
