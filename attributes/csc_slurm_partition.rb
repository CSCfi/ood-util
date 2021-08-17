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
      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        "select"
      end

      # Filter the list of partitions based on the values provided in form.yml.erb
      def filter_partitions(partitions)
        if !opts[:ignore].nil?
          # Filter out values provided in the ignore attribute on csc_slurm_partition
          partitions.select {|p| !opts[:ignore].include?(p) }
        elsif !opts[:select].nil?
          # Only include values provided in the select attribute on csc_slurm_partition
          partitions.select {|p| opts[:select].include?(p) }
        else
          partitions
        end
      end

      def get_partitions
        # Allow providing a fixed list of partitions without getting from Slurm
        if !opts[:partitions].nil?
          return opts[:partitions]
        end
        sacct_res = `#{__dir__}/../scripts/p_and_p.sh`
        res_arr = sacct_res.split('@')
        filter_partitions(res_arr[0].split(' '))
      end

      # Form label for this attribute
      # @param fmt [String, nil] formatting of form label
      # @return [String] form label
      def label(fmt: nil)
        (opts[:label] || "Partition").to_s
      end

      def select_choices
        get_partitions
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
