# frozen_string_literal: true

require 'json'
require 'time'
require 'net/http'
require 'uri'

module Backfill
  # Evidence probe (spd#149): for each inventory entry, asks ITU whether the publication page
  # and the dms_pub MSW/PDF files exist. Strictly sequential; all HTTP goes through a client
  # responding to #head(url) and #get(url) with a Backfill::SourceProbe::Response.
  class SourceProbe
    Response = Struct.new(:status, :content_type)

    PAGE_URL = 'https://www.itu.int/pub/T-SP-OB.%<number>d-%<year>d'
    FILE_URL = 'https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.%<number>d-%<year>d-OAS-%<kind>s-%<lang>s.%<ext>s'
    FILES = [%w[MSW doc], %w[MSW docx], %w[PDF pdf]].freeze
    LANGUAGES = %w[E F S].freeze
    HEAD_UNSUPPORTED = [403, 405, 501].freeze

    # Net::HTTP client; a real run only. Specs inject a stub.
    class HttpClient
      def head(url) = request(Net::HTTP::Head, url)
      def get(url) = request(Net::HTTP::Get, url)

      private

      def request(klass, url)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
          res = http.request(klass.new(uri, 'User-Agent' => 'ituob-backfill-probe (service-publications-docs#149)'))
          Response.new(res.code.to_i, res['content-type'])
        end
      end
    end

    attr_reader :requests

    def initialize(client:, cache_path:, delay: 1.0, retries: 4, backoff: 2.0,
                   sleeper: ->(s) { sleep(s) }, clock: -> { Time.now.utc })
      @client = client
      @cache_path = cache_path
      @delay = delay
      @retries = retries
      @backoff = backoff
      @sleeper = sleeper
      @clock = clock
      @cache = File.exist?(cache_path) ? JSON.parse(File.read(cache_path)) : {}
      @requests = 0
    end

    # Candidate URLs for an entry: page, then English files, then F/S (class c recovery).
    def candidates(number, year)
      page = [{ 'url' => format(PAGE_URL, number: number, year: year), 'kind' => 'page', 'lang' => nil }]
      files = LANGUAGES.flat_map do |lang|
        FILES.map do |kind, ext|
          { 'url' => format(FILE_URL, number: number, year: year, kind: kind, lang: lang, ext: ext),
            'kind' => kind.downcase, 'lang' => lang }
        end
      end
      page + files
    end

    # Probes one entry in place. Stops after the year in which an English file answers 200.
    def probe(entry)
      tried = []
      found = nil
      years(entry).each do |year|
        candidates(entry['number'], year).each do |c|
          result = lookup(c['url'])
          next unless result

          tried << c.merge(result)
          found ||= tried.last if english_file?(tried.last)
        end
        break if found
      end
      merge_into(entry, tried, found)
    end

    def probe_all(entries, &progress)
      entries.each do |entry|
        probe(entry)
        save_cache
        progress&.call(entry)
      end
    end

    def save_cache
      File.write(@cache_path, JSON.pretty_generate(@cache))
    end

    private

    def years(entry)
      y = entry['expected_year']
      [y, y - 1, y + 1]
    end

    def english_file?(row)
      row['lang'] == 'E' && row['status'] == 200 && !row['content_type'].to_s.include?('html')
    end

    # Cached answers are reused; nil means no definitive answer (429/5xx are never cached).
    def lookup(url)
      return @cache[url] if @cache.key?(url)

      res = fetch(url)
      return nil unless res

      @cache[url] = { 'status' => res.status, 'content_type' => res.content_type,
                      'checked_at' => @clock.call.iso8601 }
    end

    def fetch(url)
      attempt = 0
      loop do
        res = throttled(:head, url)
        res = throttled(:get, url) if res && HEAD_UNSUPPORTED.include?(res.status)
        return res if res && !retryable?(res.status)
        return nil if attempt >= @retries

        @sleeper.call(@backoff * (2**attempt))
        attempt += 1
      end
    end

    def throttled(verb, url)
      @sleeper.call(@delay) if @requests.positive?
      @requests += 1
      @client.public_send(verb, url)
    rescue StandardError
      nil
    end

    def retryable?(status) = status == 429 || status >= 500

    def merge_into(entry, tried, found)
      rows = tried.map { |r| r.slice('url', 'status', 'content_type', 'checked_at', 'kind', 'lang') }
      entry['evidence'] = Array(entry['evidence']).grep(String) + rows
      if found
        entry['class'] = 'b' if entry['class'] == 'unresolved'
        entry['source_url'] = found['url']
      end
      hits = tried.select { |r| r['status'] == 200 }.map { |r| r['url'] } - [found&.fetch('url')]
      entry['candidates'] = hits if hits.any?
      entry
    end
  end
end
