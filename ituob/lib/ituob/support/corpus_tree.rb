# frozen_string_literal: true

module Ituob
  module Support
    # Instance-file class resolution for the normalized ob-issues corpus:
    # ob-issues/{issue}/{rel}.yaml → the Ituob::Models class that owns
    # the instance. Single source shared by the instance-data gate
    # (scripts/validate_data_lml.rb) and the LML round-trip spec.
    module CorpusTree
      # ob-issues dataset directory slug -> amendment/general class.
      # Structured general messages resolve to their general classes; the
      # text-by-design datasets (list-v, coast-stations, bureaufax,
      # rr251, e212-icc) resolve to TextAmendment via their text.yaml.
      CLASS_BY_DIR = {
        # amendments
        'dp' => 'DPAmendment', 'e118-iin' => 'E118Amendment', 'e164-acn' => 'E164ACNAmendment',
        'e164-cc' => 'E164CCAmendment', 'e212-mnc' => 'E212MNCAmendment', 'e218-trcc' => 'E218TRCCAmendment',
        'f32-tdi' => 'F32TDIAmendment', 'f400-admd' => 'F400Amendment', 'list-viii' => 'ListVIIIAmendment',
        'm1400-icc' => 'M1400Amendment', 'nnp' => 'NNPAmendment', 'q708-ispc' => 'Q708ISPCAmendment',
        'q708-sanc' => 'Q708SANCAmendment', 't35-na' => 'T35NAAmendment', 'x121-dnic' => 'X121DNICAmendment',
        # structured general messages
        'callback-procedures' => 'GeneralCallbackProcedures', 'custom' => 'GeneralCustom',
        'ipns' => 'GeneralIpns', 'iptn' => 'GeneralIptn', 'misc-communications' => 'GeneralMiscCommunications',
        'sanc' => 'GeneralSanc', 'service-restrictions' => 'GeneralServiceRestrictions',
        'telephone-service-2' => 'GeneralTelephoneService', 'telephone-service' => 'GeneralTelephoneService',
      }.freeze

      # Class by position within the issue tree; nil = freeform, skip.
      def self.class_name_for(rel_path)
        case rel_path
        when /\Ameta\.yaml\z/ then 'IssueMetadata'
        when /\Aannexes\.yaml\z/ then nil # freeform annex snapshot (legacy)
        when %r{\Ageneral/} then nil # general messages: mixed structured/freeform
        when %r{\A([^/]+)/text\.yaml\z} then 'TextAmendment'
        when %r{\A([^/]+)/(\d+[a-z0-9.\-]*)\.yaml\z} then CLASS_BY_DIR[$1]
        end
      end

      # The corpus policy for one file: nil for freeform positions (the
      # file must not even be read — freeform payloads may contain YAML
      # aliases); otherwise the serialized `_class` overrides the
      # heuristic, since text fallbacks record the originating class.
      def self.resolve_for(rel_path, data)
        heuristic = class_name_for(rel_path)
        return nil if heuristic.nil?

        return data['_class'] if data.is_a?(Hash) && data['_class']

        heuristic
      end
    end
  end
end
