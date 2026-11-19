# frozen_string_literal: true

# Tiny valid PDFs with a self-contained Type 3 font and explicit ToUnicode map.
# Glyphs are schematic rectangles: these fixtures prove extraction/measurement,
# never visual language shaping. No renderer or system fonts are needed.
module TypesettingPdfFixture
  def write_typesetting_pdf(path, text: 'Register', embedded: true, width: 595.28, height: 841.89, x: 40, rotation: 0)
    glyphs = text.chars.uniq
    cmap = glyphs.each_with_index.map { |char, i| format('<%02X> <%s>', i + 1, char.encode('UTF-16BE').unpack1('H*')) }.join("\n")
    unicode = "/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo << /Registry (Test) /Ordering (UCS) /Supplement 0 >> def /CMapName /Test def /CMapType 2 def 1 begincodespacerange <00> <FF> endcodespacerange #{glyphs.size} beginbfchar\n#{cmap}\nendbfchar endcmap CMapName currentdict /CMap defineresource pop end end"
    # PDF content is positioned visually; reverse the visual glyph run for RTL
    # so Poppler returns its logical order (the input remains logical Unicode).
    visual = text.match?(/\p{Arabic}/) ? text.chars.reverse : text.chars
    content = "BT /F1 12 Tf #{x} 790 Td <#{visual.map { |c| format('%02X', glyphs.index(c) + 1) }.join}> Tj ET"
    stream = proc { |value| "<< /Length #{value.bytesize} >>\nstream\n#{value}\nendstream" }
    objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{width} #{height}] /Rotate #{rotation} /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
      if embedded
        "<< /Type /Font /Subtype /Type3 /Name /Fixture /FontBBox [0 0 600 700] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << #{glyphs.each_index.map { |i| "/g#{i + 1} 7 0 R" }.join(' ')} >> /Encoding << /Type /Encoding /Differences [1 #{glyphs.each_index.map { |i| "/g#{i + 1}" }.join(' ')}] >> /FirstChar 1 /LastChar #{glyphs.size} /Widths [#{Array.new(glyphs.size, 600).join(' ')}] /Resources << >> /ToUnicode 6 0 R >>"
      else
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 6 0 R >>'
      end,
      stream.call(content), stream.call(unicode), stream.call('600 0 0 0 600 700 d1 50 50 500 600 re S')
    ]
    pdf = "%PDF-1.4\n".b
    offsets = objects.each_with_index.map do |object, i|
      offset = pdf.bytesize
      pdf << "#{i + 1} 0 obj\n#{object}\nendobj\n".b
      offset
    end
    xref = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer << /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, pdf)
  end

  def write_typesetting_manifest(dir, language: 'en', title: 'Register', standard: 'TEST.1', path: 'pdf/TEST.1-2020/TEST.1-2020-E.pdf')
    entry = { 'path' => path, 'language' => language, 'title' => title, 'standard' => standard, 'edition_year' => 2020 }
    FileUtils.mkdir_p(File.join(dir, 'pdf'))
    File.write(File.join(dir, 'pdf', 'manifest.json'), JSON.generate('publications' => [entry]))
    File.join(dir, path)
  end
end
