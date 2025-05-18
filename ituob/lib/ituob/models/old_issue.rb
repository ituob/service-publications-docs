require 'lutaml/model'
require_relative 'issue_metadata'
require_relative 'issue_general'

require_relative 'general_approved_recommendations'
require_relative 'general_callback_procedures'
require_relative 'general_custom'
require_relative 'general_ipns'
require_relative 'general_iptn'
require_relative 'general_misc_communications'
require_relative 'general_org_changes'
require_relative 'general_running_annexes'
require_relative 'general_sanc'
require_relative 'general_service_restrictions'
require_relative 'general_telephone_service'

require_relative 'dp_amendment'
require_relative 'e118_amendment'
require_relative 'e164acn_amendment'
require_relative 'e164cc_amendment'
require_relative 'e212mnc_amendment'
require_relative 'e218trcc_amendment'
require_relative 'f32tdi_amendment'
require_relative 'f400_amendment'
require_relative 'm1400_amendment'
require_relative 'q708ispc_amendment'
require_relative 'q708sanc_amendment'
require_relative 'rr251_amendment'
require_relative 't35na_amendment'
require_relative 'text_amendment'
require_relative 'x121dnic_amendment'

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
            "E118Amendment" => Ituob::Models::E118Amendment # 1161-E.118 ## 
            "DPAmendment" => Ituob::Models::DPAmendment, # 994-E.164C ## 
            "E164ACNAmendment" => Ituob::Models::E164ACNAmendment, # 1015-E.164B ##
            "E164CCAmendment" => Ituob::Models::E164CCAmendment, # 1114-E.164D-Note-O/P/etc. # significant quality control problems
            "E212ICCAmendment" => Ituob::Models::E212ICCAmendment, # ?????????????????
            "E212MNCAmendment" => Ituob::Models::E212MNCAmendment, # 1162-E.212 ##
            "E218TRCCAmendment" => Ituob::Models::E218TRCCAmendment, # 1125-E.218 ## 
            "F32TDIAmendment" => Ituob::Models::F32TDIAmendment, # 980-F.32 ## 
            "F400Amendment" => Ituob::Models::F400Amendment, # 974-F.400  # some data quality issues 
            "M1400ICCAmendment" => Ituob::Models::M1400ICCAmendment, # 1060-M.1400  # some data quality issues
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
        puts "Loading issue from #{path}"
        new(
          metadata: load_file_metadata(path),
          amendments: load_file_amendment(path),
          general: load_file_general(path)
        )
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
        'E118_IIN' => E118Amendment,
        # new 
        'DP' => DPAmendment,
        'E164_ACN' => E164ACNAmendment,
        'E164_CC' => E164CCAmendment,
        'E212_ICC' => E212ICCAmendment,
        'E212_MNC' => E212MNCAmendment,
        'E218_TRCC' => E218TRCCAmendment,
        'F32_TDI' => F32TDIAmendment,
        'F400_ADMD' => F400Amendment,
        'M1400_ICC' => M1400ICCAmendment,
        'Q708_ISPC' => Q708ISPCAmendment,
        'Q708_SANC' => Q708SANCAmendment,
        'T35_NA' => T35NAAmendment,
        'X121_DNIC' => X121DNICAmendment,

        'RR.25.1' => TextAmendment,
        'BUREAUFAX' => TextAmendment,
        'List of Coast Stations and Special Service Stations' => TextAmendment, 
        'R_SP_LM.V' => TextAmendment,
        'R_SP_LN.VIII' => TextAmendment,
        'NNP' => TextAmendment,
      }

      # Parse the YAML file and extract E118 amendments
      def self.parse_amendments(amds)
        puts "Found #{amds.size} amendments"

        amds.map do |amendment|
          target = amendment['target']['publication']

          # Not all amendments have a position_on
          position_on = amendment['target']['position_on'] || nil

          unless klass = AMENDMENT_TYPE_TO_CLASS[target]
            puts "Unknown amendment type: #{target}"
            next
          end

          # Set the position_on if it exists
          klass.parse(amendment['contents']['en'], position_on: position_on, dataset_code: target)
        end.compact
      end

      GENERAL_TYPE_TO_CLASS = {
        'running_annexes' => GeneralRunningAnnexes, ## 
        'approved_recommendations' => GeneralApprovedRecommendations, ## 
        # new 
        'callback_procedures' => GeneralCallbackProcedures, ## 
        'custom' => GeneralCustom, ## 
        'ipns' => GeneralIpns,## 
        'iptn' => GeneralIptn, ## 
        'misc_communications' => GeneralMiscCommunications, ## 
        'org_changes' => GeneralOrgChanges, ## 
        'sanc' => GeneralSancs, ## 
        'service_restrictions' => GeneralServiceRestrictions,
        'telephone_service_2' => GeneralTelephoneServices # separates messages and inserts to text
      }

      # Parse the YAML file and extract general messages
      def self.parse_generals(generals)
        gen = IssueGeneral.new

        puts "Found #{generals.size} general messages"

        parsed = generals.map do |message|
          type = message['type']

          unless klass = GENERAL_TYPE_TO_CLASS[type]
            puts "Unknown amendment type: #{type}"  # Fixed variable name from 'target' to 'type'
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
