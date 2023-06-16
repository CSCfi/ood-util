begin
  require_relative '../scripts/slurm_limits'
rescue LoadError => e
  Rails.logger.error("Error loading slurm_limits.rb: #{e}")
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
        error = ""
        begin
          unless opts[:nofetchlimits]
            limits = SlurmLimits.limits
          end
          unless opts[:nosubmitscount]
            assoc_limits = SlurmLimits.assoc_limits
            submits = SlurmLimits.running
          end
        rescue Exception => e
          Rails.logger.error("Error getting limits from Slurm: #{e}\n#{e.backtrace.join("\n\t")}")
          error = e
        end
        # Allow devs to override the limits from slurm
        opts[:data] = {:limits => limits, :assoc_limits => assoc_limits, :submits => submits, :error => error}.deep_symbolize_keys.deep_merge(opts.fetch(:data, {}))
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
