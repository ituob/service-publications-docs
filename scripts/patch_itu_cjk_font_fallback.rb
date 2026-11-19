# frozen_string_literal: true

require "nokogiri"

# ITU service-publication page sequences and tables override the root font
# stack with Arial or Calibri. Keep that typography while allowing Chinese glyphs to fall
# back to the installed static font, including inside those nested overrides.
module ItuCjkFontFallback
  def self.patch(source)
    xml = Nokogiri::XML(source) { |config| config.strict.nonet }
    namespace = { "xsl" => "http://www.w3.org/1999/XSL/Transform" }
    %w[refine_page-sequence-preface refine_page-sequence-main].each do |name|
      override = xml.at_xpath("//xsl:template[@name='#{name}']//xsl:attribute[@name='font-family']", namespace)
      unless override && override.content.split(",").map(&:strip).include?("Arial")
        raise "Expected ITU Arial override missing: #{name}"
      end
    end
    fonts = xml.xpath('//@font-family | //xsl:attribute[@name="font-family"]',
                      "xsl" => "http://www.w3.org/1999/XSL/Transform")
    fonts.each do |font|
      next unless font.children.all?(&:text?)

      families = font.content.split(",").map(&:strip)
      next if (families & ["Arial", "Calibri"]).empty?
      next if families.include?("Noto Sans SC")

      font.content = "#{font.content}, Noto Sans SC"
    end
    xml.to_xml
  end
end

if $PROGRAM_NAME == __FILE__
  path = ARGV.first || File.join(
    Gem::Specification.find_by_name("metanorma-itu").full_gem_path,
    "lib/isodoc/itu/itu.service-publication.xsl"
  )
  source = File.read(path)
  patched = ItuCjkFontFallback.patch(source)
  [source, patched].zip(%w[before after]).each do |content, label|
    xml = Nokogiri::XML(content)
    values = xml.xpath('//@font-family | //xsl:attribute[@name="font-family"]',
                       "xsl" => "http://www.w3.org/1999/XSL/Transform")
      .map(&:content).select { |value| value.match?(/Arial|Calibri/) }.uniq
    puts "ITU Chinese font stacks #{label}: #{values.inspect}"
  end
  File.write(path, patched)
end
