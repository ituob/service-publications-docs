# frozen_string_literal: true

require 'nokogiri'

# Narrow table typography adjustments for the F.32 publication shard only.
module ItuF32Tables
  XSL = 'http://www.w3.org/1999/XSL/Transform'
  TARGETS = {
    'table-container-style' => 'attribute-set',
    'refine_table-container-style' => :template,
    'table-row-style' => 'attribute-set',
    'refine_table-cell-style' => :template,
    'setTableRowAttributes' => :template
  }.freeze

  def self.patch(source)
    xml = Nokogiri::XML(source) { |config| config.strict.nonet }
    ns = { 'xsl' => XSL }
    ensure_target!(xml, ns)

    patched = source.dup
    patched = patch_block(patched, 'attribute-set', 'table-container-style') do |block|
      block = replace_value(block, 'font-size', '10pt', '8pt', 'table-container-style')
      block = replace_or_insert_attribute(block, 'font-family', 'Arial', 'table-container-style')
      replace_or_insert_attribute(block, 'line-height', '9pt', 'table-container-style')
    end
    patched = patch_block(patched, 'template', 'refine_table-container-style') do |block|
      replace_value(block, 'font-family', 'Calibri', 'Arial', 'refine_table-container-style')
    end
    patched = patch_block(patched, 'attribute-set', 'table-row-style') do |block|
      replace_value(block, 'min-height', '4mm', '3.175mm', 'table-row-style')
    end
    patched = patch_block(patched, 'template', 'refine_table-cell-style') do |block|
      patch_service_publication_padding(block)
    end

    patched = patch_block(patched, 'template', 'setTableRowAttributes') do |block|
      replace_value(block, 'min-height', '5mm', '3.175mm', 'setTableRowAttributes')
    end
    %w[marginLeftRight1_ marginLeftRight2_].each do |name|
      pattern = %r{(<xsl:variable name="#{name}">)(20|12)(\s*</xsl:variable>)}
      raise "Expected ITU F.32 page margin missing: #{name}" unless patched.scan(pattern).one?

      patched = patched.sub(pattern) { "#{Regexp.last_match(1)}12#{Regexp.last_match(3)}" }
    end
    patched = numeric_table_footnotes(patched)

    ensure_patched!(patched)
    patched
  end

  def self.ensure_target!(xml, ns)
    TARGETS.each do |name, kind|
      xpath = "//xsl:#{kind}[@name='#{name}']"
      raise "Expected ITU F.32 table style missing: #{name}" unless xml.xpath(xpath, ns).one?
    end
    node = xml.at_xpath("//xsl:attribute-set[@name='table-container-style']/xsl:attribute[@name='font-size']", ns)
    raise 'Expected ITU F.32 table container font-size missing' unless node

    %w[min-height].each do |name|
      node = xml.at_xpath("//xsl:attribute-set[@name='table-row-style']/xsl:attribute[@name='#{name}']", ns)
      raise "Expected ITU F.32 table row #{name} missing" unless node
    end
    template = xml.at_xpath("//xsl:template[@name='refine_table-cell-style']", ns)
    unless template&.xpath(".//xsl:if[contains(@test, \"service-publication\")]/xsl:attribute[@name='padding-top']",
                           ns)&.one?
      raise 'Expected ITU service-publication cell padding missing'
    end
  end
  private_class_method :ensure_target!

  def self.patch_block(source, kind, name)
    pattern = %r{<xsl:#{kind} name="#{Regexp.escape(name)}">.*?</xsl:#{kind}>}m
    matches = source.scan(pattern)
    raise "Expected ITU F.32 table style missing: #{name}" unless matches.one?

    source.sub(pattern) { yield Regexp.last_match[0] }
  end
  private_class_method :patch_block

  def self.replace_value(block, attribute, old_value, new_value, label)
    pattern = %r{(<xsl:attribute name="#{Regexp.escape(attribute)}">)(#{Regexp.escape(old_value)}|#{Regexp.escape(new_value)})(</xsl:attribute>)}
    matches = block.scan(pattern)
    raise "Unexpected ITU F.32 table style value: #{label}/#{attribute}" unless matches.one?

    block.sub(pattern) { "#{Regexp.last_match(1)}#{new_value}#{Regexp.last_match(3)}" }
  end
  private_class_method :replace_value

  def self.replace_or_insert_attribute(block, attribute, value, label)
    pattern = %r{(<xsl:attribute name="#{Regexp.escape(attribute)}">)(Calibri|Arial|#{Regexp.escape(value)})(</xsl:attribute>)}
    matches = block.scan(pattern)
    return block.sub(pattern) { "#{Regexp.last_match(1)}#{value}#{Regexp.last_match(3)}" } if matches.one?
    raise "Unexpected ITU F.32 table style value: #{label}/#{attribute}" unless matches.empty?

    size_pattern = %r{(<xsl:attribute name="font-size">(?:10pt|8pt)</xsl:attribute>)}
    raise 'Expected ITU F.32 table container font-size missing' unless block.scan(size_pattern).one?

    block.sub(size_pattern) do
      "#{Regexp.last_match(1)}\n\t\t<xsl:attribute name=\"#{attribute}\">#{value}</xsl:attribute>"
    end
  end
  private_class_method :replace_or_insert_attribute

  def self.patch_service_publication_padding(source)
    pattern = %r{(<xsl:if test="\$doctype = 'service-publication'">.*?<xsl:attribute name="padding-top">)(1mm|0mm)(</xsl:attribute>.*?</xsl:if>)}m
    matches = source.scan(pattern)
    raise 'Expected ITU service-publication cell padding missing' unless matches.one?

    source.sub(pattern) { "#{Regexp.last_match(1)}0mm#{Regexp.last_match(3)}" }
  end
  private_class_method :patch_service_publication_padding

  # The printed F.32 notes use numeric references. Apply the same label to the
  # link and note body; targets and note text remain untouched.
  def self.numeric_table_footnotes(source)
    return source if source.include?('name="f32-numeric-table-footnotes"')

    template = <<~XML
      <xsl:template name="f32-numeric-table-footnotes"
        xmlns:mn="https://www.metanorma.org/ns/standoc"
        match="mn:table//mn:fmt-fn-label//text()" priority="10">
        <xsl:choose>
          <xsl:when test="string-length(.) = 1 and contains('abcdefghijklmnopqrstuvwxyz', .)">
            <xsl:value-of select="string-length(substring-before('abcdefghijklmnopqrstuvwxyz', .)) + 1"/>
          </xsl:when>
          <xsl:otherwise><xsl:value-of select="."/></xsl:otherwise>
        </xsl:choose>
      </xsl:template>
      <xsl:template xmlns:mn="https://www.metanorma.org/ns/standoc"
        match="mn:table//mn:fmt-fn-label//text()" mode="update_xml_step1" priority="10">
        <xsl:call-template name="f32-numeric-table-footnotes"/>
      </xsl:template>
      <xsl:template xmlns:mn="https://www.metanorma.org/ns/standoc"
        match="mn:table//mn:fn/@reference | mn:table//mn:fmt-fn-body/@reference"
        mode="update_xml_step1" priority="10">
        <xsl:attribute name="reference"><xsl:call-template name="f32-numeric-table-footnotes"/></xsl:attribute>
      </xsl:template>
    XML
    source.sub('</xsl:stylesheet>', "#{template}</xsl:stylesheet>")
  end
  private_class_method :numeric_table_footnotes

  def self.ensure_patched!(source)
    xml = Nokogiri::XML(source) { |config| config.strict.nonet }
    ns = { 'xsl' => XSL }
    values = {
      "//xsl:attribute-set[@name='table-container-style']/xsl:attribute[@name='font-size']" => '8pt',
      "//xsl:attribute-set[@name='table-container-style']/xsl:attribute[@name='font-family']" => 'Arial',
      "//xsl:attribute-set[@name='table-container-style']/xsl:attribute[@name='line-height']" => '9pt',
      "//xsl:template[@name='setTableRowAttributes']//xsl:attribute[@name='min-height']" => '3.175mm',
      "//xsl:template[@name='refine_table-container-style']//xsl:attribute[@name='font-family']" => 'Arial',
      "//xsl:attribute-set[@name='table-row-style']/xsl:attribute[@name='min-height']" => '3.175mm',
      "//xsl:template[@name='refine_table-cell-style']//xsl:if[contains(@test, \"service-publication\")]/xsl:attribute[@name='padding-top']" => '0mm'
    }
    values.each do |xpath, value|
      node = xml.at_xpath(xpath, ns)
      raise "Expected patched ITU F.32 table style missing: #{xpath}" unless node&.content == value
    end
  end
  private_class_method :ensure_patched!
end

if $PROGRAM_NAME == __FILE__
  path = ARGV.first
  unless path
    candidates = Gem.path.flat_map do |gem_path|
      Dir.glob(File.join(gem_path, 'gems/metanorma-itu-*/lib/isodoc/itu/itu.service-publication.xsl'))
    end.uniq
    raise 'Expected exactly one installed metanorma-itu service-publication stylesheet' unless candidates.one?

    path = candidates.first
  end
  source = File.read(path)
  patched = ItuF32Tables.patch(source)
  File.write(path, patched) unless patched == source
  puts "ITU F.32 table stylesheet #{patched == source ? 'already patched' : 'patched'}: #{path}"
end
