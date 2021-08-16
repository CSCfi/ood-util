begin
    require_relative '../scripts/slurm_limits'
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
          unless opts[:nofetchlimits]
            limits = SlurmLimits::limits
          end
          unless opts[:nosubmitscount]
            assoc_limits = SlurmLimits::assoc_limits
            submits = SlurmLimits::submits
          end
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
