begin
  require_relative '../scripts/slurm_project_partition'
  require_relative '../scripts/slurm_reservation'
rescue LoadError
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

      def select_choices
        @@select_choices ||=
          begin
            reservations = SlurmReservation.reservations
            get_projects.collect do |p|
              full_name = p[:description] == p[:name] ? p[:name] : "#{p[:name]} (#{p[:description]})"
              data_option_for = reservations.filter_map do |res|
                res_name = res.name.gsub(/_/, '-')
                allowed = (res.accounts + res.groups).uniq
                {"data-option-for-csc-slurm-reservation-#{res_name}".to_sym => false} if !allowed.empty? && !allowed.include?(p[:name])
              end
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
