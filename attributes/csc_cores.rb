module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCCores] the attribute object
    def self.build_csc_cores(opts = {})
      Attributes::CSCCores.new("csc_cores", opts)
    end
  end

  module Attributes
    class CSCCores< Attribute

      # Extend the default initializer
      def initialize(id, opts = {})
        # Field will be validated using the cpu value from csc_slurm_limits
        opts[:data] = {:max => "cpu"}.deep_symbolize_keys.deep_merge(opts.fetch(:data, {}))
        opts[:min] ||= 1
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
        (opts[:label] || "Number of CPU cores").to_s
      end

      def value
        (opts[:value] || "1").to_s
      end

      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        # { script: { native: ["-c", value] } } would be the optimal here but the arrays in the
        # submission hash are not merged, submission needs to be handled in submit.yml.erb
        {}
      end
    end
  end
end
