# frozen_string_literal: true

module Ituob
  # Auditors compare two rendered outputs (e.g. the deployed Jekyll site
  # against the new Astro build) and report per-section content gaps.
  #
  # Unlike verifiers (which check invariants on the source data), auditors
  # operate on already-rendered HTML.
  module Auditors
    autoload :ContentParity, 'ituob/auditors/content_parity'
  end
end
