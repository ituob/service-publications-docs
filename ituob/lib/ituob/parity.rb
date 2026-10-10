# frozen_string_literal: true

# Parent namespace file for +Ituob::Parity+. Declares leaf autoloads.
#
# Parity tooling: URL mapping from deployed Jekyll permalinks to
# Astro URLs, link/content parity auditors, validation reports.
# Lives in the ituob gem so both the audit scripts and their specs
# can require the helpers cleanly (no `require_relative` in scripts).

module Ituob
  module Parity
    autoload :UrlMap, 'ituob/parity/url_map'
  end
end
