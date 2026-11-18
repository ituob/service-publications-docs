# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../scripts/patch_itu_f32_tables'

RSpec.describe ItuF32Tables do
  let(:stylesheet) do
    <<~XML
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:variable name="marginLeftRight1_">20</xsl:variable>
        <xsl:variable name="marginLeftRight2_">20</xsl:variable>
        <xsl:template name="setTableRowAttributes">
          <xsl:if test="$doctype = 'service-publication'">
            <xsl:attribute name="min-height">5mm</xsl:attribute>
          </xsl:if>
        </xsl:template>
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
    expect(described_class.patch(patched)).to eq(patched)
  end

  it 'overrides the service-publication row minimum and matches page margins and leading' do
    expect(xml.at_xpath("//xsl:template[@name='setTableRowAttributes']//xsl:attribute[@name='min-height']", ns).content)
      .to eq('3.175mm')
    expect(xml.at_xpath("//xsl:attribute-set[@name='table-container-style']/xsl:attribute[@name='line-height']", ns).content)
      .to eq('9pt')
    %w[marginLeftRight1_ marginLeftRight2_].each do |name|
      expect(xml.at_xpath("//xsl:variable[@name='#{name}']", ns).content.strip).to eq('12')
    end
    expect { described_class.patch(stylesheet.sub('>5mm<', '>6mm<')) }
      .to raise_error(/Unexpected ITU F.32 table style value/)
  end

  it 'uses the same numeric labels for table note links and bodies and preserves prose' do
    template = xml.xpath("//xsl:template[@name='f32-numeric-table-footnotes' or @priority='10']", ns).map(&:to_xml).join
    transform = Nokogiri::XSLT(<<~XML)
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:output method="text"/>
        <xsl:template match="/"><xsl:apply-templates mode="update_xml_step1"/></xsl:template>
        #{template}
      </xsl:stylesheet>
    XML
    document = Nokogiri::XML(<<~XML)
      <doc xmlns="https://www.metanorma.org/ns/standoc">
        <table><fmt-fn-label><semx element="autonum">a</semx></fmt-fn-label>
          <fmt-fn-body><fmt-fn-label><semx element="autonum">a</semx></fmt-fn-label>Note a retained</fmt-fn-body>
          <fmt-fn-label><semx element="autonum">b</semx></fmt-fn-label>
          <fmt-fn-label><semx element="autonum">3</semx></fmt-fn-label>
        </table><fmt-fn-label><semx element="autonum">a</semx></fmt-fn-label>
      </doc>
    XML
    expect(transform.transform(document).text.gsub(/\s+/, ' ').strip).to eq('1 1Note a retained 2 3 a')
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
