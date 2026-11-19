# frozen_string_literal: true

require "spec_helper"
require_relative "../../../scripts/patch_itu_cjk_font_fallback"

RSpec.describe ItuCjkFontFallback do
  let(:stylesheet) do
    <<~XML
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                      xmlns:fo="http://www.w3.org/1999/XSL/Format" version="1.0">
        <xsl:template name="refine_page-sequence-preface">
          <xsl:attribute name="font-family">Arial, STIX Two Math</xsl:attribute>
        </xsl:template>
        <xsl:template name="refine_page-sequence-main">
          <xsl:attribute name="font-family">Arial, STIX Two Math</xsl:attribute>
        </xsl:template>
        <fo:block font-family="Arial" font-weight="bold" font-style="italic"/>
        <fo:table font-family="Calibri"/>
        <fo:block font-family="Traditional Arabic, Times New Roman"/>
        <xsl:attribute name="font-family">Arial, <xsl:value-of select="$fonts"/></xsl:attribute>
      </xsl:stylesheet>
    XML
  end
  let(:patched) { described_class.patch(stylesheet) }
  let(:xml) { Nokogiri::XML(patched) }

  it "preserves Arial while giving page sequences and nested blocks a Chinese fallback" do
    expect(xml.at_xpath("//xsl:attribute", "xsl" => "http://www.w3.org/1999/XSL/Transform").text)
      .to eq("Arial, STIX Two Math, Noto Sans SC")
    block = xml.at_xpath("//fo:block", "fo" => "http://www.w3.org/1999/XSL/Format")
    expect(block["font-weight"]).to eq("bold")
    expect(block["font-style"]).to eq("italic")
    expect(xml.xpath("//@font-family").map(&:value)).to eq([
      "Arial, Noto Sans SC", "Calibri, Noto Sans SC", "Traditional Arabic, Times New Roman"
    ])
  end

  it "rejects an incompatible installed stylesheet" do
    expect { described_class.patch(stylesheet.sub("refine_page-sequence-main", "changed-main")) }
      .to raise_error(/Expected ITU Arial override missing/)
  end

  it "preserves computed font stacks and is idempotent" do
    expect(patched).to include('<xsl:value-of select="$fonts"/>')
    expect(described_class.patch(patched)).to eq(patched)
  end
end
