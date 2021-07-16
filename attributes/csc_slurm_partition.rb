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

      def get_partitions
        sacct_res = `/appl/opt/ood_util/scripts/p_and_p.sh`
        res_arr = sacct_res.split('@')
        slurm_partitions = res_arr[0].split(' ')       
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
