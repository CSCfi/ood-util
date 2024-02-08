module SmartAttributes
  class AttributeFactory
    def self.build_csc_gpu_type(opts = {})
      Attributes::CSCGPUType.new("csc_gpu_type", opts)
    end
  end

  module Attributes
    class CSCGPUType < Attribute
      def initialize(id, opts = {})
        opts[:cacheable] = opts.fetch(:cacheable, true)
        super(id, opts)
      end

      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        "select"
      end

      # Form label for this attribute
      # @param fmt [String, nil] formatting of form label
      # @return [String] form label
      def label(fmt: nil)
        (opts[:label] || "GPU").to_s
      end

      def select_choices(*)
        @@select_choices ||= begin
            # A hash with of gpu types with valid partitions for each gpu_type (gpu_type => [partitions])
            gpu_types = SlurmLimits.limits
              .entries
              .each_with_object({}) { |(part, limits), hsh|
              limits[:gpu_types].each { |gpu_type|
                # Add each GPU type
                hsh[gpu_type] = hsh.fetch(gpu_type, []).append(part)
              }
            }
            all_partitions = SlurmLimits.limits.keys
            # A hash of the gpu types, with data-option for invalid partitions (all partitions - valid)
            gpu_types = gpu_types.map { |gpu_type, partitions|
              [gpu_type, (all_partitions - partitions).map { |part| { :"data-option-for-csc-slurm-partition-#{part}" => false } }]
            }.to_h
            gpu_types.map { |gpu_type, data_options| [gpu_type, gpu_type, *data_options] }
          end
      end

      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        {}
      end
    end
  end
end
