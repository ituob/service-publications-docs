# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    class GeneralCustom < GeneralMessage
      attribute :ob_issue_no, :string
      attribute :contents, HashOrText
      attribute :text, :string
      attribute :title, MultilingualString
      attribute :recommendation, :string

      key_value do
        map 'title', with: { from: :title_from_hash, to: :title_to_hash }
        map 'recommendation', to: :recommendation
        map 'ob_issue_no', to: :ob_issue_no
        map 'contents', to: :contents
        map 'text', to: :text
      end

      # OB 1202 stores `title: {en: ''}`: an explicit blank, which must
      # survive a read/write. MultilingualString itself omits blank cells
      # (parsers build it from blank spreadsheet cells), so the explicit
      # blank is preserved here, for this one field only.
      def title_from_hash(model, value)
        model.title = MultilingualString.new(**value.transform_keys(&:to_sym).slice(*MultilingualString.attributes.keys)) if value.is_a?(Hash)
      end

      def title_to_hash(model, doc)
        return if model.title.nil?

        hash = model.title.to_hash
        hash['en'] = '' if model.title.en == ''
        doc['title'] = hash
      end
    end
  end
end
