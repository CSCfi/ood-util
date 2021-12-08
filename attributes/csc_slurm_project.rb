begin
  require_relative '../scripts/slurm_project_partition'
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
        SlurmProjectPartition.projects
      end

      # Form label for this attribute
      # @param fmt [String, nil] formatting of form label
      # @return [String] form label
      def label(fmt: nil)
        (opts[:label] || "Project").to_s
      end

      def select_choices
        get_projects.collect { |p| [p, p] }
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
