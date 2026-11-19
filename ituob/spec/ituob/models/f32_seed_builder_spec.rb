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
                                     "PHCB" => "Cebu")
      expect(allocations.values.grep(/--[A-Z]{2}/)).to be_empty
      expect(complete.legacy_rows.map { |entry| entry.office_code.to_s }).not_to include("PHBG")
    end

    it "retains multi-network offices as their own contexts, not as part of the next name" do
      expect(relative.keys).to include(["--AR", "Arica"], ["--CA", "Calama"], ["--CH", "Chillán"],
                                       ["--CO", "Curico"], ["--IQ", "Iquique"], ["--LS", "La Serena"],
                                       ["--OV", "Ovalle"], ["--TL", "Talca"], ["--OO", "Porto"],
                                       ["--JJ", "33052 CERVIGNANO DEL FRIULI"], ["--NX", "All others"],
                                       ["--SA", "Sanaa"], ["--TZ", "Taiz / Tayz"], ["--HO", "Hodeidah"])
      # Yemen prints two networks (YN- - and Unitel YE- -), so its relative codes stay relative.
      expect(allocations.keys).not_to include("YNSA", "YNTZ", "YNHO")
      names = complete.contexts.map { |context| context.entry.telegraph_office_name&.en.to_s }
      expect(names.grep(/--[A-Z]{2}/).reject { |name| name.include?("-->") }).to be_empty
    end

    it "splits a 4-letter code the extraction joined to the end of a name cell into its own office" do
      expect(allocations).to include("ABBR" => "Berat", "ABMT" => "Burrel", "ABDR" => "Durres", "ABKO" => "Korce",
                                     "ABKR" => "Kruje", "ABKU" => "Kukes", "ABLU" => "Lushnje",
                                     "DZOR" => "Oran", "CLAD" => "Acund", "CLAG" => "Angol", "WBBN" => "Barbados / Barbade")
      expect(allocations["DZAX"]).to eq("All others")
      expect(allocations["CLLD"]).to eq("Andes (Los)")
    end

    it "keeps no other printed office code inside any name" do
      codes = complete.allocations.map(&:office_code).to_set
      embedded = complete.allocations.select do |entry|
        entry.telegraph_office_name.en.to_s.scan(/\b[A-Z]{4}\b/).any? { |word| codes.include?(word) && word != entry.office_code }
      end
      expect(embedded.map { |entry| [entry.office_code, entry.telegraph_office_name.en] }).to be_empty
    end

    it "leaves uppercase 4-letter names alone when the country has no such code prefix" do
      expect(allocations.values).to include("WIEN", "GIZA", "PORT SAID C", "BELBEIS")
    end

    it "accounts for every printed office row" do
      expect(complete.allocations.length).to eq(1088)
    end

    describe "printed-row cells" do
      let(:printed) { complete.contexts.select { |context| context.kind == "printed-row" }.map { |context| context.entry } }

      it "keeps the full network code when a footnote mark follows it (GIBRALTAR GK- -)" do
        codes = printed.select { |entry| entry.source_language == "en" && entry.source_cells[0] == "GIBRALTAR" }
                       .map { |entry| entry.source_cells[2] }
        expect(codes.reject(&:empty?)).to all(start_with("GK- -"))
        expect(codes.reject(&:empty?)).not_to be_empty
        expect(complete.contexts.map { |context| context.entry.network_code }.compact).not_to include("GK-")
      end

      it "gives the first word of an office name to the name cell, not the code cell (RE / All destinations)" do
        rows = printed.select { |entry| entry.source_language == "en" && entry.source_cells[4] == "REXX" }
        expect(rows.map(&:source_cells).map { |cells| cells.values_at(2, 3) }).to eq([["RE", "All destinations"]])
      end

      it "does not glue the second line of a name continued after a slash to the next office (HONDURAS)" do
        rows = printed.select { |entry| entry.source_language == "fr" && entry.source_cells[4] == "HOPC" }
        expect(rows.map { |entry| entry.source_cells[3] }).to eq(["Puerto Cortes"])
      end

      it "keeps the footnote mark printed beside a resolved English code (SPAIN ESTT 1))" do
        rows = printed.select { |entry| entry.source_language == "en" && entry.source_row == 622 }
        expect(rows.map(&:source_cells)).to eq([["", "", "", "Telegrams with service", "ESTT"], ["", "", "", "", "1)"]])
      end

      it "reads a superscript printed as the nodes \"1\" and \")\" as one mark (CYPRUS, Spanish)" do
        cells = printed.select { |entry| entry.source_language == "es" && entry.source_cells[4] == "CYNC" }
                       .map { |entry| entry.source_cells[3] }
        expect(cells).to eq(["LEFKOSIA 1)"])
        expect(printed.flat_map(&:source_cells)).not_to include(match(/\d \)/))
      end

      it "keeps a long note line that starts in the ROA column in the note (SAUDI ARABIA 3, French and Spanish)" do
        notes = printed.select { |entry| %w[fr es].include?(entry.source_language) && entry.source_cells.length == 1 }
                       .map { |entry| entry.source_cells.first }
        expect(notes.grep(/Al Jamoom, Al Kariq/).map { |note| note.sub(/Al Jamoom.*/, "").strip })
          .to eq(["et destinés aux bureaux suivants:", "destinados a las oficinas siguientes:"])
        expect(printed.select { |entry| entry.source_cells.length == 5 }.map { |entry| entry.source_cells[1] })
          .not_to include(match(/\AAl Jamoom/))
      end

      it "gives the ROA word folded into the country node to the ROA cell (PORTUGAL, MADERA PT Comunicações)" do
        rows = printed.select { |entry| entry.source_cells[1].to_s.end_with?("Comunicações, S.A., Lisboa") && entry.source_cells[0].start_with?("MADERA") }
        expect(rows.map { |entry| entry.source_cells.first(2) }).to eq([["MADERA", "PT Comunicações, S.A., Lisboa"]] * 3)
      end

      it "gives the ROA folded into the country node to the ROA cell (PORTUGAL, AÇORES Non précisé / Sin encaminamiento)" do
        rows = printed.select { |entry| entry.source_cells[0].to_s.start_with?("AÇORES") }
        expect(rows.map { |entry| entry.source_cells.first(2) }).to include(
          ["AÇORES – AZORES – AZORES", "Non précisé"],
          ["AÇORES – AZORES – AZORES", "Sin encaminamiento"],
        )
      end

      it "places a 15-character word that starts at the text edge of a wide node in its own column (UNITED STATES, Spanish)" do
        rows = printed.select { |entry| entry.source_language == "es" && entry.source_cells[1] == "Communications, Inc." }
        expect(rows.map { |entry| entry.source_cells[0] }).to eq(["", ""])
      end
    end
  end
end
