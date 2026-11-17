# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/provider_publication_rendering'

RSpec.describe 'E.218 localized provider grouping' do
  include ProviderPublicationRendering

  let(:root) { File.expand_path('../../..', __dir__) }
  let(:directory) { File.join(root, 'documents/T-SP-E.218-2017') }
  let(:catalog) { Ituob::Catalogs::Registers.find('E218_TRCC') }
  let(:model) { Ituob::Catalogs::Registers.parser_class_for(catalog.register_id).attributes.fetch(:entries).type }
  let(:metadata) { Ituob::Provider.new(data_root: root).locale(register: catalog.slug).to_liquid }
  let(:rows) do
    [
      { 'tmcc_code' => '201', 'country_or_area' => { 'en' => 'Shared', 'fr' => 'Alpha' },
        'note' => { 'en' => 'Mobile note', 'fr' => 'Première note' } },
      { 'tmcc_code' => '202', 'country_or_area' => { 'en' => 'Shared', 'fr' => 'Bêta' },
        'note' => { 'en' => 'Mobile note', 'fr' => 'Dernière note' } },
      { 'tmcc_code' => '203', 'country_or_area' => { 'en' => 'Other', 'fr' => 'Gamma' } }
    ]
  end
  let(:rendered) do
    render_publication_table(directory, 'table', rows.map { |row| model.from_hash(row).to_liquid }, metadata, 'fr')
  end

  it 'keeps both translated countries and their codes in alphabetical order' do
    alphabetical = rendered.split('alphabetical order', 2).last
    expect(alphabetical).to include('| 201 | Alpha |', '| 202 | Bêta |', '| 203 | Gamma |')
    expect(alphabetical.index('| 201')).to be < alphabetical.index('| 202')
    expect(alphabetical.index('| 202')).to be < alphabetical.index('| 203')
  end

  it 'preserves the legacy last matching translated note and permits absent notes' do
    expect(rendered).to include('[[note_a]]Dernière note')
    expect(rendered).not_to include('Liquid error')
  end
end
