# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../scripts/patch_itu_f32_tables'

RSpec.describe ItuF32Tables do
  let(:stylesheet) do
    <<~XML
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:attribute-set name="table-container-style">
          <xsl:attribute name="font-size">10pt</xsl:attribute>
          <xsl:attribute name="space-after">18pt</xsl:attribute>
        </xsl:attribute-set>
        <xsl:template name="refine_table-container-style">
          <xsl:if test="$doctype = 'service-publication'">
            <xsl:attribute name="font-family">Calibri</xsl:attribute>
          </xsl:if>
        </xsl:template>
        <xsl:attribute-set name="table-row-style">
          <xsl:attribute name="min-height">4mm</xsl:attribute>
        </xsl:attribute-set>
        <xsl:template name="refine_table-cell-style">
          <xsl:if test="$doctype = 'service-publication'">
            <xsl:attribute name="padding-top">1mm</xsl:attribute>
          </xsl:if>
          <xsl:attribute name="padding-bottom">2mm</xsl:attribute>
        </xsl:template>
        <xsl:attribute-set name="unrelated-style">
          <xsl:attribute name="font-size">10pt</xsl:attribute>
          <xsl:attribute name="min-height">4mm</xsl:attribute>
          <xsl:attribute name="padding-top">1mm</xsl:attribute>
        </xsl:attribute-set>
      </xsl:stylesheet>
    XML
  end
  let(:patched) { described_class.patch(stylesheet) }
  let(:xml) { Nokogiri::XML(patched) }
  let(:ns) { { 'xsl' => 'http://www.w3.org/1999/XSL/Transform' } }

  it 'sets the F.32 table font, row height, and service-publication cell padding' do
    original = Nokogiri::XML(stylesheet)
    expect(original.at_xpath("//xsl:attribute-set[@name='table-container-style']/xsl:attribute[@name='font-size']",
                             ns).content)
      .to eq('10pt')
    expect(original.at_xpath(
      "//xsl:template[@name='refine_table-container-style']//xsl:attribute[@name='font-family']", ns
    ).content)
      .to eq('Calibri')
    expect(original.at_xpath("//xsl:attribute-set[@name='table-row-style']/xsl:attribute[@name='min-height']",
                             ns).content)
      .to eq('4mm')
    expect(original.at_xpath(
      "//xsl:template[@name='refine_table-cell-style']//xsl:if[contains(@test, \"service-publication\")]/xsl:attribute[@name='padding-top']", ns
    ).content)
      .to eq('1mm')
    expect(xml.at_xpath("//xsl:attribute-set[@name='table-container-style']/xsl:attribute[@name='font-size']",
                        ns).content)
      .to eq('8pt')
    expect(xml.at_xpath("//xsl:attribute-set[@name='table-container-style']/xsl:attribute[@name='font-family']",
                        ns).content)
      .to eq('Arial')
    expect(xml.at_xpath("//xsl:template[@name='refine_table-container-style']//xsl:attribute[@name='font-family']",
                        ns).content)
      .to eq('Arial')
    expect(xml.at_xpath("//xsl:attribute-set[@name='table-row-style']/xsl:attribute[@name='min-height']", ns).content)
      .to eq('3.175mm')
    expect(xml.at_xpath(
      "//xsl:template[@name='refine_table-cell-style']//xsl:if[contains(@test, \"service-publication\")]/xsl:attribute[@name='padding-top']", ns
    ).content)
      .to eq('0mm')
  end

  it 'preserves unrelated styles and is idempotent' do
    expect(xml.at_xpath("//xsl:attribute-set[@name='table-container-style']/xsl:attribute[@name='space-after']",
                        ns).content)
      .to eq('18pt')
    expect(xml.at_xpath("//xsl:template[@name='refine_table-cell-style']//xsl:attribute[@name='padding-bottom']",
                        ns).content)
      .to eq('2mm')
    unrelated = xml.xpath("//xsl:attribute-set[@name='unrelated-style']/xsl:attribute", ns)
    expect(unrelated.map(&:content)).to eq(%w[10pt 4mm 1mm])
    expect(patched).to eq(stylesheet
      .sub('<xsl:attribute name="font-size">10pt</xsl:attribute>', "<xsl:attribute name=\"font-size\">8pt</xsl:attribute>\n\t\t<xsl:attribute name=\"font-family\">Arial</xsl:attribute>")
      .sub('<xsl:attribute name="font-family">Calibri</xsl:attribute>', '<xsl:attribute name="font-family">Arial</xsl:attribute>')
      .sub('<xsl:attribute name="min-height">4mm</xsl:attribute>', '<xsl:attribute name="min-height">3.175mm</xsl:attribute>')
      .sub('<xsl:attribute name="padding-top">1mm</xsl:attribute>', '<xsl:attribute name="padding-top">0mm</xsl:attribute>'))
    expect(described_class.patch(patched)).to eq(patched)
  end

  it 'rejects stylesheet versions missing a targeted template or attribute' do
    expect { described_class.patch(stylesheet.sub('name="table-row-style"', 'name="changed-row-style"')) }
      .to raise_error(/Expected ITU F.32 table style missing/)
    expect do
      described_class.patch(stylesheet.sub('<xsl:attribute name="padding-top">1mm</xsl:attribute>',
                                           '<xsl:attribute name="padding-left">1mm</xsl:attribute>'))
    end
      .to raise_error(/Expected ITU service-publication cell padding missing/)
  end
end
