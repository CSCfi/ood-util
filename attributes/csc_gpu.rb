module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCGPU] the attribute object
    def self.build_csc_gpu(opts = {})
      Attributes::CSCGPU.new("csc_gpu", opts)
    end
  end

  module Attributes
    class CSCGPU < Attribute

      # Extend the default initializer
      def initialize(id, opts = {})
        # Validate field using the gres/gpu:v100 in csc_slurm_limits
        opts[:data] = {:max => opts[:type].nil? ? "gres/gpu" : "gres/gpu:#{opts[:type]}"}.deep_symbolize_keys.deep_merge(opts.fetch(:data, {}))
        opts[:min] = opts[:min].nil? ? 1 : opts[:min]
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
        (opts[:label] || opts[:type].nil? ? "Number of GPUs" : "Number of GPUs (#{opts[:type].capitalize})").to_s
      end

      def value
        (opts[:value] || "1").to_s
      end

      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        # { script: { native: ["--gres=gpu:v100:#{value}"] } } would be the optimal here but the
        # arrays in the submission hash are not merged, submission needs to be handled in submit.yml.erb
        {}
      end
    end
  end
end
