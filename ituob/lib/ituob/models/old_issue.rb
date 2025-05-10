require 'lutaml/model'
require_relative 'e118_amendment'
require_relative 'issue_metadata'
require_relative 'issue_general'
require_relative 'general_running_annexes'
require_relative 'general_approved_recommendations'

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
            "E118Amendment" => Ituob::Models::E118Amendment
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

      # TODO: Support more amendment types
      AMENDMENT_TYPE_TO_CLASS = {
        'E118_IIN' => E118Amendment,
        #  BUREAUFAX
        #  DP
        #  E164_ACN
        #  E164_CC
        #  E212_ICC
        #  E212_MNC
        #  E218_TRCC
        #  F32_TDI
        #  F400_ADMD
        #  List of Coast Stations and Special Service Stations
        #  M1400_ICC
        #  NNP
        #  Q708_ISPC
        #  Q708_SANC
        #  R_SP_LM.V
        #  R_SP_LN.VIII
        #  RR.25.1
        #  T35_NA
        #  X121_DNIC
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
          klass.parse(amendment['contents']['en'], position_on: position_on)
        end.compact
      end

      # TODO: Support more general types
      GENERAL_TYPE_TO_CLASS = {
        'running_annexes' => GeneralRunningAnnexes,
        'approved_recommendations' => GeneralApprovedRecommendations,
        # 'callback_procedures' => GeneralCallbackProcedures,
        # 'custom' => GeneralCustom,
        # 'ipns' => GeneralIpns,
        # 'iptn' => GeneralIptn,
        # 'misc_communications' => GeneralMiscCommunications,
        # 'org_changes' => GeneralOrgChanges,
        # 'sanc' => GeneralSanc,
        # 'service_restrictions' => GeneralServiceRestrictions,
        # 'telephone_service_2' => GeneralTelephoneService.
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
