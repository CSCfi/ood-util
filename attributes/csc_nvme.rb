module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCNVME] the attribute object
    def self.build_csc_nvme(opts = {})
      Attributes::CSCNVME.new("csc_nvme", opts)
    end
  end

  module Attributes
    class CSCNVME < Attribute

      def initialize(id, opts = {})
        # Validate using gres/nvme from csc_slurm_limits
        opts[:data] = {:max => "gres/nvme"}.deep_symbolize_keys.deep_merge(opts.fetch(:data, {}))
        opts[:min] ||= 0
        opts[:cacheable] = opts.fetch(:cacheable, false)
        super(id, opts)
      end

      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        "number_field"
      end

      # Form label for this attribute
      # @param fmt [String, nil] formatting of form label
      # @return [String] form label
      def label(fmt: nil)
        (opts[:label] || "Local disk (GB)").to_s
      end

      def value
        #(opts[:value] || "0").to_s
        "0" # Force 0 until LUMI-D NVME works
      end

      # Hide for all apps until LUMI-D NVME works
      def fixed?
        true
      end

      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        # { script: { native: ["--gres=nvme:#{value}"] } } would be the optimal here but the arrays
        # in the submission hash are not merged, submission needs to be handled in submit.yml.erb
        {}
      end
    end
  end
end
