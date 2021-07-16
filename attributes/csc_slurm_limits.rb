begin
  require '/appl/opt/ood_util/scripts/slurm_limits.rb'
rescue LoadError 
end
module SmartAttributes
  class AttributeFactory
    def self.build_csc_slurm_limits(opts = {})
      Attributes::CSCSlurmLimits.new("csc_slurm_limits", opts)
    end
  end

  module Attributes
    class CSCSlurmLimits < Attribute

      def initialize(id, opts={})
        begin 
          limits = SlurmLimits::limits
          assoc_limits = SlurmLimits::assoc_limits
          submits = SlurmLimits::submits
        rescue
        end
        # Allow devs to override the limits from slurm
        opts[:data] = {:limits => limits, :assoc_limits => assoc_limits, :submits => submits}.deep_symbolize_keys.deep_merge(opts.fetch(:data, {}))
        super(id, opts)
      end

      def widget
        "hidden_field"
      end

      def submit(fmt: nil)
        {}
      end
    end
  end
end
