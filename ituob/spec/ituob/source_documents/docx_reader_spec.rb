# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'zip'

RSpec.describe Ituob::SourceDocuments::DocxReader do
  def write_docx(path)
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream('word/document.xml') do |io|
        io.write(<<~XML)
          <w:document xmlns:w="#{described_class::W_NS}"><w:body>
            <w:p><w:r><w:t>Operational Bulletin</w:t></w:r></w:p>
            <w:tbl>
              <w:tr><w:tc><w:p><w:r><w:t>Country</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Code</w:t></w:r></w:p></w:tc></w:tr>
              <w:tr><w:tc><w:p><w:r><w:t>Ruritania</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>999</w:t></w:r></w:p></w:tc></w:tr>
            </w:tbl>
          </w:body></w:document>
        XML
      end
    end
  end

  # A fresh process, so no earlier spec has already loaded document.rb:
  # DocxReader builds Rows and Tables before anything touches Document.
  it 'reads tables in a fresh process before Document is referenced' do
    script = <<~'RUBY'
      require 'ituob'
      doc = Ituob::SourceDocuments::DocxReader.read(ARGV.fetch(0))
      p doc.tables.map { |t| t.rows.map(&:cells) }
    RUBY
    Dir.mktmpdir do |dir|
      docx = File.join(dir, 'issue.docx')
      write_docx(docx)

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, '-rbundler/setup', '-Iituob/lib', '-e', script, docx,
        chdir: File.expand_path('../../../..', __dir__),
      )

      expect(status).to be_success, stderr
      expect(stdout.chomp).to eq('[[["Country", "Code"], ["Ruritania", "999"]]]')
    end
  end
end
