# frozen_string_literal: true

require "spec_helper"
require "ituob/registers"

RSpec.describe Ituob::Registers::Strategies::Lir, "E212 country translations" do
  let(:register_id) { "E212_MNC" }
  let(:builder) { Ituob::Registers::StateBuilder.new(register_id) }
  let(:countries) do
    { "en" => "Luxembourg", "fr" => "Luxembourg", "es" => "Luxemburgo",
      "ru" => "Люксембург", "zh" => "卢森堡", "ar" => "لكسمبرغ" }
  end
  let(:printed_countries) { { "en" => "Luxembourg (updated)" } }
  let(:rows) do
    ["270 07", "270 99"].map do |key|
      { "mcc_mnc_codes" => key, "country_or_area" => printed_countries, "networks" => "Updated #{key}" }
    end
  end
  let(:change) do
    Ituob::Registers::Change.new(
      type: "LIR", register_id: register_id, identifier: { "code" => "P 10" },
      data: { "entries" => rows },
    )
  end

  before do
    ["270 07", "270 99"].each do |key|
      builder.set_entry(key, {
        "mcc_mnc_codes" => key, "country_or_area" => countries,
        "networks" => "Old #{key}", "unprinted" => "drop me",
      })
    end
  end

  it "preserves unprinted translations for 270 07 and 270 99 while refreshing the printed row" do
    described_class.call(builder, change, "mcc_mnc_codes")

    rows.each do |row|
      key = row.fetch("mcc_mnc_codes")
      expect(builder.entries.fetch(key)).to eq(row.merge("country_or_area" => countries.merge(printed_countries)))
    end
    expect(countries.fetch("en")).to eq("Luxembourg")
    expect(printed_countries.keys).to eq(["en"])
    expect(builder.lapsed_keys).to be_empty
  end

  context "when another translation is printed" do
    let(:printed_countries) { { "en" => "Luxembourg", "fr" => "Luxembourg (updated)" } }

    it "uses the printed translation and retains the other languages" do
      described_class.call(builder, change, "mcc_mnc_codes")

      expect(builder.entries.fetch("270 07").fetch("country_or_area")).to eq(countries.merge(printed_countries))
    end
  end

  context "when the repetition omits the country field" do
    let(:rows) { [{ "mcc_mnc_codes" => "270 07", "networks" => "Updated 270 07" }] }

    it "retains all stored country translations" do
      described_class.call(builder, change, "mcc_mnc_codes")

      expect(builder.entries.fetch("270 07")).to eq(rows.first.merge("country_or_area" => countries))
    end
  end

  context "when the repeated country is nil" do
    let(:printed_countries) { nil }

    it "retains all stored country translations" do
      described_class.call(builder, change, "mcc_mnc_codes")

      expect(builder.entries.fetch("270 07")).to eq(rows.first.merge("country_or_area" => countries))
    end
  end

  it "inserts a printed row absent from the register without inventing translations" do
    builder.remove_entry("270 07")

    described_class.call(builder, change, "mcc_mnc_codes")

    expect(builder.entries.fetch("270 07")).to eq(rows.first)
  end

  context "with another register" do
    let(:register_id) { "F1" }

    it "continues to replace the stored row with the printed row" do
      described_class.call(builder, change, "mcc_mnc_codes")

      expect(builder.entries.fetch("270 07")).to eq(rows.first)
    end
  end
end
