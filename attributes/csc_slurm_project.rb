begin
  require_relative '../scripts/slurm_project_partition'
  require_relative '../scripts/slurm_reservation'
rescue LoadError => e
  Rails.logger.error("Error loading slurm_project_partition.rb or slurm_reservation.rb: #{e}")
end

module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCProject] the attribute object
    def self.build_csc_slurm_project(opts = {})
      Attributes::CSCProject.new("csc_slurm_project", opts)
    end
  end

  module Attributes
    class CSCProject < Attribute
      def initialize(id, opts={})
        opts[:cacheable] = opts.fetch(:cacheable, true)
        super(id, opts)
      end
      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        "select"
      end

      def get_projects
        SlurmProjectPartition.projects_full
      end

      # Form label for this attribute
      # @param fmt [String, nil] formatting of form label
      # @return [String] form label
      def label(fmt: nil)
        (opts[:label] || "Project").to_s
      end

      # returns an array with data-option-for (dynamic form JS) that hides the project when it
      # can't be used by the currently selected reservation
      # e.g. project_1234 is not on the list of accounts that can access the myreservation reservation:
      # [{:"data-option-for-csc-slurm-reservation-myreservation": false}]
      def reservations_data_option_for(project)
        @reservations ||= SlurmReservation.reservations
        data_option_for = @reservations.filter_map do |res|
          res_name = res.name.gsub(/_/, '-')
          allowed = (res.accounts + res.groups).uniq
          {"data-option-for-csc-slurm-reservation-#{res_name}".to_sym => false} if !allowed.empty? && !allowed.include?(project)
        end
      end

      def select_choices
        @@select_choices ||=
          begin
            get_projects.collect do |p|
              # Append description in parenthesis if not same as project name
              full_name = p[:description] == p[:name] ? p[:name] : "#{p[:name]} (#{p[:description]})"
              data_option_for = reservations_data_option_for(p[:name])
              [full_name, p[:name], *data_option_for]
            end
          end
      end

      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        { script: { accounting_id: value.blank? ? nil : value.strip } }
      end
    end
  end
end
