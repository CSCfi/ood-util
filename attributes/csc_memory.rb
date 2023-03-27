module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCMemory] the attribute object
    def self.build_csc_memory(opts = {})
      Attributes::CSCMemory.new("csc_memory", opts)
    end
  end

  module Attributes
    class CSCMemory < Attribute

      def initialize(id, opts = {})
        # Limit memory based on CPU cores selected
        max_mem_per_cpu = {:attribute => :csc_cores, :value => :max_mem_per_cpu, :message => "Memory exceeds maximum memory per CPU" }
        # Validate field using mem from csc_slurm_limits
        opts[:data] = {:max => "mem", :max_per => [max_mem_per_cpu]}.deep_symbolize_keys.deep_merge(opts.fetch(:data, {}))
        opts[:min] ||= 1
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
        (opts[:label] || "Memory (GB)").to_s
      end

      def value
        (opts[:value] || "1").to_s
      end

      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        # { script: { native: ["--mem=#{value}"] } } would be the optimal here but the arrays in the
        # submission hash are not merged, submission needs to be handled in submit.yml.erb
        {}
      end
    end
  end
end
