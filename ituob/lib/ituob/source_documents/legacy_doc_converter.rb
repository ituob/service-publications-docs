# frozen_string_literal: true

require 'open3'
require 'tmpdir'

module Ituob
  module SourceDocuments
    # Convert a legacy .doc file (Word 97-2003) to .docx with headless
    # LibreOffice, then read it with DocxReader so tables are kept.
    #
    # The conversion runs in a tmpdir that also holds a throwaway
    # LibreOffice profile, so parallel runs do not share a user profile
    # lock. The tmpdir is removed whether the conversion succeeds or not.
    class LegacyDocConverter
      class ConversionError < StandardError; end

      EXECUTABLE = 'soffice'

      def self.available?
        !executable_path.nil?
      end

      def self.executable_path
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
          candidate = File.join(dir, EXECUTABLE)
          return candidate if File.file?(candidate) && File.executable?(candidate)
        end
        nil
      end

      def self.read(path)
        new.read(path)
      end

      def read(path)
        Dir.mktmpdir('ituob-doc-') do |dir|
          document = DocxReader.read(convert(path, dir))
          document.source_path = File.expand_path(path)
          document.conversion = :soffice
          document
        end
      end

      private

      def convert(path, dir)
        output, status = Open3.capture2e(*command(path, dir))
        docx = File.join(dir, "#{File.basename(path.to_s, '.*')}.docx")
        return docx if status.success? && File.exist?(docx)

        raise ConversionError, "soffice could not convert #{path} to .docx: #{output.strip}"
      end

      def command(path, dir)
        [
          EXECUTABLE,
          "-env:UserInstallation=file://#{File.join(dir, 'profile')}",
          '--headless',
          '--convert-to', 'docx',
          '--outdir', dir,
          path.to_s
        ]
      end
    end
  end
end
