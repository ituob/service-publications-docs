# frozen_string_literal: true

require 'digest'
require_relative 'provider_publication_rendering'

module MainPublicationRendering
  include ProviderPublicationRendering

  def publication_content_digest(source, restored_notes: false)
    if restored_notes
      source = source.sub(/\. \[\[note_n\]\].*?(?=\. \[\[note_q\]\])/m, '')
    end
    lines = source.lines.map(&:strip).reject(&:empty?)
    Digest::SHA256.hexdigest(lines.join("\n"))
  end
end
