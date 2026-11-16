# frozen_string_literal: true

require 'spec_helper'

# The general-message classes (and IssueMetadata) are the write path for
# forms: a value read from the corpus must come back unchanged. The
# instance round-trip spec compares class output with class output, so
# it cannot see a loss inside the class; this spec compares against the
# stored file itself.
RSpec.describe 'General messages are lossless against the stored corpus' do
  def stored_shape(obj)
    case obj
    when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stored_shape(v) unless v.nil? }
    when Array then obj.map { |v| stored_shape(v) }
    when Time then [:time, obj.utc.strftime('%FT%T.%LZ')]
    when Date then [:date, obj.to_s]
    else obj
    end
  end

  def lossless_files
    Dir.children(OB_ISSUES_ROOT).grep(/\A\d+\z/).sort.flat_map do |issue|
      dir = File.join(OB_ISSUES_ROOT, issue)
      Dir.glob(File.join(dir, '**', '*.yaml')).sort.filter_map do |path|
        rel = path.delete_prefix("#{dir}/")
        next if Ituob::Support::CorpusTree.class_name_for(rel).nil?

        data = YAML.load_file(path, permitted_classes: [Date, Time], aliases: true)
        name = Ituob::Support::CorpusTree.resolve_for(rel, data)
        next unless name&.start_with?('General') || name == 'IssueMetadata'

        [path, "#{issue}/#{rel}", Ituob::Models.const_get(name), data]
      end
    end
  end

  it 'returns every stored General* and IssueMetadata file unchanged (read, then write)' do
    lossy = lossless_files.filter_map do |path, rel, klass, data|
      written = klass.from_yaml(File.read(path), permitted_classes: [Date, Time]).to_hash
      rel unless stored_shape(written) == stored_shape(data)
    rescue StandardError => e
      "#{rel}: #{e.class}: #{e.message.lines.first.strip}"
    end

    expect(lossy).to be_empty, "#{lossy.length} lossy:\n  #{lossy.first(10).join("\n  ")}"
  end

  describe 'field types that used to lose data' do
    def reload(klass, yaml)
      klass.from_yaml(yaml, permitted_classes: [Date, Time]).to_hash
    end

    it 'keeps GeneralCustom title and recommendation' do
      out = reload(Ituob::Models::GeneralCustom,
                   "type: custom\ntitle:\n  en: Telegram Service\nrecommendation: F.1\ncontents: {}\n")
      expect(out).to include('title' => { 'en' => 'Telegram Service' }, 'recommendation' => 'F.1')
    end

    it 'keeps IssueMetadata languages as booleans and dates as stored' do
      out = reload(Ituob::Models::IssueMetadata,
                   "id: 1000\nlanguages:\n  en: true\npublication_date: 2012-03-15T14:49:49.000Z\ncutoff_date: 2012-03-01\n")
      expect(out['languages']).to eq('en' => true)
      expect(out['id']).to eq(1000)
      expect(out['publication_date']).to eq(Time.utc(2012, 3, 15, 14, 49, 49))
      expect(out['cutoff_date']).to eq(Date.new(2012, 3, 1))
    end

    it 'keeps an approved-recommendation timestamp on its stored instant and free text as text' do
      parsed = Ituob::Models::GeneralApprovedRecommendations.parse(
        'type' => 'approved_recommendations',
        'items' => { "G.168  " => Time.utc(2012, 1, 31, 23), 'G.993.2' => '2015' }
      ).to_hash
      expect(parsed['items']).to eq(
        [{ 'recommendation' => 'G.168', 'approved_date' => Time.utc(2012, 1, 31, 23) },
         { 'recommendation' => 'G.993.2', 'approved_date' => '2015' }]
      )
    end

    it 'does not raise on an approved_recommendations message without items' do
      expect { Ituob::Models::GeneralApprovedRecommendations.parse('type' => 'approved_recommendations') }
        .not_to raise_error
    end

    it 'keeps a source-asset string in misc_communications contents' do
      out = reload(Ituob::Models::GeneralMiscCommunications,
                   "type: misc_communications\ncontents: general/misc_comms.adoc\n")
      expect(out['contents']).to eq('general/misc_comms.adoc')
    end

    it 'keeps service-restriction page numbers as integers' do
      out = reload(Ituob::Models::GeneralServiceRestrictions,
                   "type: service_restrictions\nitems:\n- country:\n    en: Seychelles\n  ob: 1006\n  page: 13\n")
      expect(out['items']).to eq([{ 'country' => { 'en' => 'Seychelles' }, 'ob' => 1006, 'page' => 13 }])
    end

    it 'keeps telephone-service communications bodies as documents, dates as stored, empty lists empty' do
      out = reload(Ituob::Models::GeneralTelephoneService, <<~YAML)
        type: telephone_service_2
        contents:
        - country_name:
            en: Gambia
          phone_code: '220'
          communications:
          - date: 2012-02-06T20:41:49.860Z
            contents:
              en:
                type: doc
                content: []
        - country_name:
            en: Nowhere
          communications: []
      YAML
      first, second = out['contents']
      expect(first['communications'].first['contents']).to eq('en' => { 'type' => 'doc', 'content' => [] })
      expect(first['communications'].first['date']).to eq(Time.utc(2012, 2, 6, 20, 41, 49.86r))
      expect(second['communications']).to eq([])
    end
  end

  describe 'OldIssue.load_issue_dir' do
    %w[1000 1012].each do |issue|
      it "loads issue #{issue}, whose general messages include types without a hand-written parse" do
        dir = File.join(FIXTURE_ROOT, issue)
        skip 'itu-ob-data submodule not checked out' unless File.directory?(dir)

        expect(Ituob::Models::OldIssue.load_issue_dir(dir).general.messages).not_to be_empty
      end
    end
  end
end
