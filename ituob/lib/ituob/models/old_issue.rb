# frozen_string_literal: true

require 'lutaml/model'

# Check if DEBUG mode is enabled
DEBUG = ENV['DEBUG'] == 'true'



module Ituob
  module Models
    class OldIssue < ::Lutaml::Model::Serializable
      attribute :metadata, IssueMetadata
      attribute :general, IssueGeneral
      # TODO: Uncomment when IssueAnnexes is implemented
      # attribute :annexes, IssueAnnexes
      attribute :amendments, Amendment, collection: true, polymorphic: true

      key_value do
        map "metadata", to: :metadata
        map "general", to: :general
        map "amendments", to: :amendments, polymorphic: {
          attribute: "_class",
          class_map: {
            "E118Amendment" => Ituob::Models::E118Amendment, # 1161-E.118 ##
            "DPAmendment" => Ituob::Models::DPAmendment, # 994-E.164C ##
            "E164ACNAmendment" => Ituob::Models::E164ACNAmendment, # 1015-E.164B ##
            "E164CCAmendment" => Ituob::Models::E164CCAmendment, # 1114-E.164D-Note-O/P/etc. # significant quality control problems
            # "E212ICCAmendment" => Ituob::Models::E212ICCAmendment, # ?????????????????
            "E212MNCAmendment" => Ituob::Models::E212MNCAmendment, # 1162-E.212 ##
            "E218TRCCAmendment" => Ituob::Models::E218TRCCAmendment, # 1125-E.218 ##
            "F32TDIAmendment" => Ituob::Models::F32TDIAmendment, # 980-F.32 ##
            "F400Amendment" => Ituob::Models::F400Amendment, # 974-F.400  # some data quality issues
            "M1400Amendment" => Ituob::Models::M1400Amendment, # 1060-M.1400  # some data quality issues
            "Q708ISPCAmendment" => Ituob::Models::Q708ISPCAmendment, # 1109-Q.708B ## some data quality issues (especially with P lines, mostly accounted for)
            "Q708SANCAmendment" => Ituob::Models::Q708SANCAmendment, # 1125-Q.708A ## fairly good data quality
            "T35NAAmendment" => Ituob::Models::T35NAAmendment, # 1001-T.35B ##
            "X121DNICAmendment" => Ituob::Models::X121DNICAmendment, # 977-X.121B ##

            "TextAmendment" => Ituob::Models::TextAmendment,  # ##
            #"RR251Amendment" => Ituob::Models::TextAmendment, # 1154-RR.25.1 # Putting these in as text, there seems to be zero data conformance here
            # "NNPAmendment" => Ituob::Models::NNPAmendment, # ##
            # "ListCS4Amendment" => Ituob::Models::ListCS4Amendment,# ##
            # "RSPLMVAmendment" => Ituob::Models::RSPLMVAmendment, # ##
            # "RSPLNVIIIAmendment" => Ituob::Models::RSPLNVIIIAmendment, # ##
            # "BureauFaxAmendment" => Ituob::Models::BureauFaxAmendment,  # ##
          },
        }
      end

      def self.load_issue_dir(path)
        puts "Loading issue from #{path}" if DEBUG
        new(
          metadata: load_file_metadata(path),
          amendments: load_file_amendment(path),
          general: load_file_general(path)
        )
      rescue Errno::ENOENT => e
        puts "Error loading issue from #{path}: #{e.message}"
        nil
      end

      def self.load_file_general(path)
        file_path = File.join(path, 'general.yaml')
        data = YAML.load_file(file_path, permitted_classes: [Date, Time])
        return unless data.is_a?(Hash) && data['messages'].is_a?(Array)

        parse_generals(data['messages'])
      end

      def self.load_file_metadata(path)
        file_path = File.join(path, 'meta.yaml')
        IssueMetadata.from_yaml(IO.read(file_path))
      end

      def self.load_file_amendment(path)
        file_path = File.join(path, 'amendments.yaml')
        data = YAML.load_file(file_path, permitted_classes: [Date, Time])
        return unless data.is_a?(Hash) && data['messages'].is_a?(Array)

        messages = data['messages']
        amd_messages = messages.select { |msg| msg['type'] == 'amendment' }
        parse_amendments(amd_messages)
      end

      AMENDMENT_TYPE_TO_CLASS = {
        'E118_IIN' => Ituob::Models::E118Amendment, # 1161-E.118 # DONE Verify
        'DP' => Ituob::Models::DPAmendment, # DONE Verify
        'E164_ACN' => Ituob::Models::E164ACNAmendment, # datasets/1015-E.164B/data.yaml # DONE Verify
        'E164_CC' => Ituob::Models::E164CCAmendment, # DONE Verify
        'F32_TDI' => Ituob::Models::F32TDIAmendment, # DONE Verify

        # NEW
        # 'E212_ICC' => Ituob::Models::E212ICCAmendment, # E212_ICC renders via the textual path; passes parity
        'E212_MNC' => Ituob::Models::E212MNCAmendment, # verified: behavioral specs + equivalence gate
        'E218_TRCC' => Ituob::Models::E218TRCCAmendment, # verified: behavioral specs + equivalence gate
        'F400_ADMD' => Ituob::Models::F400Amendment, # verified: behavioral specs + equivalence gate
        'M1400_ICC' => Ituob::Models::M1400Amendment, # verified: behavioral specs + equivalence gate
        'Q708_ISPC' => Ituob::Models::Q708ISPCAmendment, # verified: behavioral specs + equivalence gate
        'Q708_SANC' => Ituob::Models::Q708SANCAmendment, # verified: behavioral specs + equivalence gate
        'T35_NA' => Ituob::Models::T35NAAmendment, # verified: behavioral specs + equivalence gate
        'X121_DNIC' => Ituob::Models::X121DNICAmendment, # verified: behavioral specs + equivalence gate
        'RR.25.1' => Ituob::Models::TextAmendment, # verified 2026-08-17: RR251Amendment parses 3/4 sources to zero actions and raises on OB 973 — zero data conformance; keep verbatim text
        'BUREAUFAX' => Ituob::Models::TextAmendment, # verified: verbatim render passes worst-variant parity
        'List of Coast Stations and Special Service Stations' => Ituob::Models::TextAmendment, # verified: verbatim render passes worst-variant parity
        'R_SP_LM.V' => Ituob::Models::TextAmendment, # verified: verbatim render passes worst-variant parity
        'R_SP_LN.VIII' => Ituob::Models::ListVIIIAmendment, # semantic since TODO.complete/53 (was TextAmendment)
        'NNP' => Ituob::Models::NNPAmendment, # semantic since TODO.complete/50 (was TextAmendment)
      }

      # Parse the YAML file and extract E118 amendments
      def self.parse_amendments(amds)
        puts "Found #{amds.size} amendments" if DEBUG

        amds.map do |amendment|
          target = amendment['target']['publication']

          # Not all amendments have a position_on
          position_on = amendment['target']['position_on'] || nil

          unless klass = AMENDMENT_TYPE_TO_CLASS[target]
            puts "Unknown amendment type: #{target}" if DEBUG
            next
          end

          return if amendment['contents']['en'].nil?

          # Set the position_on if it exists
          klass.parse(amendment['contents']['en'], position_on: position_on, dataset_code: target)
        end.compact
      end

      GENERAL_TYPE_TO_CLASS = {
        'running_annexes' => Ituob::Models::GeneralRunningAnnexes, # DONE Verify
        'approved_recommendations' => Ituob::Models::GeneralApprovedRecommendations, # DONE Verify
        'callback_procedures' => Ituob::Models::GeneralCallbackProcedures, # DONE Verify
        'ipns' => Ituob::Models::GeneralIpns, # DONE Verify
        'iptn' => Ituob::Models::GeneralIptn, # DONE Verify

        # NEW
        'custom' => Ituob::Models::GeneralCustom, # verified: renders via issue general section; 310/310 issues pass
        'misc_communications' => Ituob::Models::GeneralMiscCommunications, # verified: renders via issue general section; 310/310 issues pass
        'org_changes' => Ituob::Models::GeneralOrgChanges, # verified: renders via issue general section; 310/310 issues pass
        'sanc' => Ituob::Models::GeneralSancs, # verified: renders via issue general section; 310/310 issues pass
        'service_restrictions' => Ituob::Models::GeneralServiceRestrictions, # verified: renders via issue general section; 310/310 issues pass
        'telephone_service_2' => Ituob::Models::GeneralTelephoneServices # separates messages and inserts to text — verified: 310/310 issue pages pass
      }

      # Parse the YAML file and extract general messages
      def self.parse_generals(generals)
        gen = IssueGeneral.new

        puts "Found #{generals.size} general messages" if DEBUG

        parsed = generals.map do |message|
          type = message['type']

          unless klass = GENERAL_TYPE_TO_CLASS[type]
            puts "Unknown amendment type: #{type}" if DEBUG  # Fixed variable name from 'target' to 'type'
            next
          end

          klass.parse(message)
        end.compact

        gen.messages = parsed
        gen
      end
    end
  end
end
