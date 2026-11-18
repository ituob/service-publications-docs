# frozen_string_literal: true

require "spec_helper"
require "ituob/models"
require "ituob/helpers"
require "yaml"

RSpec.describe "Unmapped amendment notes and references" do
  let(:source) do
    data = YAML.load_file(
      File.join(FIXTURE_ROOT, issue.to_s, "amendments.yaml"),
      permitted_classes: [Date, Time],
    )
    data.fetch("messages").find do |message|
      message.dig("target", "publication") == publication
    end.dig("contents", "en")
  end

  context "with the effective-date footnote in OB 982" do
    let(:issue) { 982 }
    let(:publication) { "E164_ACN" }
    let(:parsed) { Ituob::Models::E164ACNAmendment.parse(source) }

    it "keeps the date as an amendment note and preserves the entries" do
      expect(parsed.notes.join(" ")).to include("As from October 2011")
      expect(parsed.to_hash.fetch("notes").join(" ")).to include("As from October 2011")
      entries = parsed.actions.flat_map(&:entries)
      expect(entries.map(&:country_code)).to include("359", "689", "34", "58")
      expect(entries.map { |entry| entry.mobile_telephone_numbers.en }).to include("6, 71-74")
    end

    it "keeps glossary paragraphs alongside the date note" do
      glossary = "Notes common to Numerical and Alphabetical lists of ITU-T Recommendation E.164"
      source.fetch("content") << {
        "type" => "paragraph",
        "content" => [{ "type" => "text", "text" => glossary }],
      }

      expect(parsed.notes).to include(glossary)
      expect(parsed.notes.join(" ")).to include("As from October 2011")
    end
  end

  [1123, 1330].each do |issue_number|
    context "with the designation footnote in OB #{issue_number}" do
      let(:issue) { issue_number }
      let(:publication) { "Q708_ISPC" }
      let(:parsed) { Ituob::Models::Q708ISPCAmendment.parse(source) }

      it "keeps the designation and glossary as notes without adding an entry" do
        expect(parsed.notes.join(" ")).to include("This designation is without prejudice")
        expect(parsed.notes.join(" ")).to include("ISPC:")
        expect(parsed.actions.flat_map(&:entries).map(&:ipsc)).to all(match(/\A\d-\d{3}-\d\z/))
        expect(parsed.actions.flat_map(&:entries)).not_to be_empty
      end
    end
  end

  context "with multiline number patterns in OB 1001" do
    let(:issue) { 1001 }
    let(:publication) { "E164_ACN" }

    it "preserves every printed Brazil number pattern and single-line codes" do
      parsed = Ituob::Models::E164ACNAmendment.parse(source)
      entries = parsed.actions.flat_map(&:entries)
      brazil = entries.find { |entry| entry.country_code == "55" }
      expect(brazil.country_or_area.en).to eq("Brazil (Federal Republic of)")
      expect(brazil.mobile_telephone_numbers.en).to eq(
        "area code + 6XXX XXXX area code + 7XXX XXXX area code + 8XXX XXXX " \
        "area code + 9XXX XXXX area code + 9XXXX XXXX",
      )
      expect(entries.find { |entry| entry.country_code == "226" }.mobile_telephone_numbers.en).to eq("60, 68, 7")
    end
  end

  [974, 991].each do |issue_number|
    context "with split Part II reference columns in OB #{issue_number}" do
      let(:issue) { issue_number }
      let(:publication) { "R_SP_LN.VIII" }

      it "keeps the Part III page references with the station contacts" do
        parsed = Ituob::Models::ListVIIIAmendment.parse(source)
        station = parsed.actions.flat_map(&:entries).find do |entry|
          entry.name.to_s.start_with?(issue == 974 ? "Kyiv" : "Khabarovsk")
        end
        expect(station.part_iii_reference).to eq("166 f 175 e 184 s")
        expect(station.part_ii_reference).to eq("")
        expect(station.contact).to include(issue == 974 ? "centre@ucrf.gov.ua" : "info@dforadio.ru")
        expect(station.postal_address).not_to be_empty
      end
    end
  end
end
