# frozen_string_literal: true

require 'net/http'
require 'json'
require 'base64'
require 'pathname'

module Ituob
  module SourceDocuments
    # Read a PDF file into a Document via the Z.AI GLM-OCR API.
    #
    # Mirrors the Ruby approach used in +oimlsmart/vocab/scripts/ocr_pdf_glm.rb+
    # — same API, same response shape. The reader is pluggable: future
    # adapters could call a local Tesseract or ABBYY instead.
    class PdfReader
      API_URL = 'https://api.z.ai/api/paas/v4/layout_parsing'.freeze
      MODEL = 'glm-ocr'
      MAX_PAGES_PER_REQUEST = 20

      def self.read(path, total_pages: nil, api_key: nil)
        new.read(path, total_pages: total_pages, api_key: api_key)
      end

      def read(path, total_pages: nil, api_key: nil)
        api_key ||= load_api_key
        pdf_b64 = Base64.strict_encode64(File.binread(path))
        page_count = total_pages || page_count_via_pdfinfo(path)
        markdown = ocr_all_pages(api_key, pdf_b64, page_count)
        paragraphs = markdown.split(/\n\s*\n/).map(&:strip).reject(&:empty?)

        Document.new(source_path: File.expand_path(path), paragraphs: paragraphs, tables: [])
      end

      private

      def load_api_key
        key_file = Pathname.new(Dir.home) / '.zai-api-key'
        raise "API key file not found: #{key_file}" unless key_file.exist?

        content = key_file.read.strip
        return content.split('=', 2).last.strip.delete('"\'') if content.include?('=')

        content
      end

      def page_count_via_pdfinfo(path)
        out, = Open3.capture2('pdfinfo', path.to_s)
        return 100 unless out =~ /^Pages:\s+(\d+)/

        Regexp.last_match(1).to_i
      end

      def ocr_all_pages(api_key, pdf_b64, total_pages)
        total_pages ||= 20
        parts = []
        (0...total_pages).step(MAX_PAGES_PER_REQUEST) do |start|
          finish = [start + MAX_PAGES_PER_REQUEST - 1, total_pages - 1].min
          result = call_ocr(api_key, pdf_b64, start, finish)
          md = extract_markdown(result)
          parts << md if md
          break if finish >= total_pages - 1
        end
        parts.join("\n\n---\n\n")
      end

      def call_ocr(api_key, pdf_b64, start_page, end_page)
        body = {
          'model' => MODEL,
          'file'  => "data:application/pdf;base64,#{pdf_b64}",
          'start_page_id' => start_page,
          'end_page_id' => end_page,
        }
        uri = URI(API_URL)
        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/json'
        req['Authorization'] = "Bearer #{api_key}"
        req.body = JSON.generate(body)

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) do |http|
          response = http.request(req)
          raise "HTTP #{response.code}: #{response.body[0, 200]}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        end
      end

      def extract_markdown(result)
        return nil unless result

        data = result['data'] || result
        md_results = data['md_results'] || result['md_results'] || []
        return nil if md_results.empty?

        md_results.map.with_index do |item, i|
          if item.is_a?(Hash)
            page = item['page_id'] || i
            "<!-- Page #{page} -->\n#{item['md'] || item['text'] || ''}"
          else
            item.to_s
          end
        end.join("\n\n")
      end
    end
  end
end
