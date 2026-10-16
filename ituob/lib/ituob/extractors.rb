# frozen_string_literal: true

# Parent namespace file for +Ituob::Extractors+.
#
# Extractors convert source content (ProseMirror docs, .adoc tables) into
# +Domain::ChangeObject+ instances. They are the "parser" side of the
# pipeline.
#
# Each extractor follows a common protocol (see +Base+). Adding a new
# extractor for a new publication means:
#   1. Subclass +ProseMirrorExtractor+ (or +Base+ if format differs).
#   2. Override +extract_entries+ if the layout differs from the default.
#   3. Register it in +Catalogs::Publications::REGISTRY+.
# No other module changes — open for extension.

module Ituob
  module Extractors
    autoload :Base, 'ituob/extractors/base'
    autoload :ProseMirror, 'ituob/extractors/prosemirror'
    autoload :ProseMirrorWalker, 'ituob/extractors/prosemirror_walker'
    autoload :AmendmentExtractor, 'ituob/extractors/amendment_extractor'
    autoload :GeneralMessageExtractor, 'ituob/extractors/general_message_extractor'
  end
end
