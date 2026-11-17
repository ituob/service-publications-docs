# frozen_string_literal: true

module OfficialPdfGateHelpers
  def gate_write(relative, content = "PDF")
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def gate_source(publication, language = "E", suffix = "")
    gate_write("documents/T-SP-#{publication}/T-SP-#{publication}#{suffix}-#{language}.adoc", "= Source")
  end

  def gate_generated(key)
    gate_write("generated/shard/T-SP-#{key[0...-2]}/#{key[0...-2]}/#{key}.pdf")
  end

  def gate_baseline(entries)
    gate_write("docs/pdf/official-baseline.json", JSON.generate(entries))
  end

  def gate_index(entries)
    gate_write("docs/pdf/official-pdfs.json", JSON.generate(entries))
  end

  def gate_run(*arguments)
    described_class.main(["--root", root, "--generated", File.join(root, "generated")] + arguments)
  end
end
