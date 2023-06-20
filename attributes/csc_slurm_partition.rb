begin
  require_relative '../scripts/slurm_project_partition'
rescue LoadError => e
  Rails.logger.error("Error loading slurm_project_partition.rb: #{e}")
end
module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCPartition] the attribute object
    def self.build_csc_slurm_partition(opts = {})
      Attributes::CSCPartition.new("csc_slurm_partition", opts)
    end
  end

  module Attributes
    class CSCPartition < Attribute

      def initialize(id, opts={})
        @@partitions ||= SlurmProjectPartition.partitions_with_data
        opts[:cacheable] = opts.fetch(:cacheable, true)
        opts[:help] ||= '<div id="partition_gpu_help" style="display: none;">The selected partition will reserve 1 GPU (<span id="partition_gpu_type"></span>).</div>'
        super(id, opts)
      end

      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        "select"
      end

      # Filter the list of partitions based on the values provided in form.yml.erb
      def filter_partitions(partitions)
        if !opts[:ignore].nil?
          # Filter out values provided in the ignore attribute on csc_slurm_partition
          partitions.select {|partition, projects| !opts[:ignore].include?(partition) }
        elsif !opts[:select].nil?
          # Only include values provided in the select attribute on csc_slurm_partition
          partitions.select {|partition, projects| opts[:select].include?(partition) }
        else
          partitions
        end
      end

      def get_partitions
        # Allow providing a fixed list of partitions without getting from Slurm
        if !opts[:partitions].nil?
          return opts[:partitions]
        end
        filter_partitions(@@partitions)
      end

      # Form label for this attribute
      # @param fmt [String, nil] formatting of form label
      # @return [String] form label
      def label(fmt: nil)
        (opts[:label] || "Partition").to_s
      end

      def select_choices
        get_partitions.map { |partition, project_data| [partition, *project_data]}
      end

      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        { script: { queue_name: value.blank? ? nil : value.strip } }
      end
    end
  end
end
