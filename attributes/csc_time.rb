module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCTime] the attribute object
    def self.build_csc_time(opts = {})
      Attributes::CSCTime.new("csc_time", opts)
    end
  end

  module Attributes
    class CSCTime < Attribute
      
      def initialize(id, opts = {})
        # Validate using time from csc_slurm_limits, parse the value as type time on validation
        opts[:data] = {:max => "time", :type => "time"}.deep_symbolize_keys.deep_merge(opts.fetch(:data, {}))
        # Pattern currently allows invalid time values such as seconds/minutes/hours > 60
        opts[:pattern] ||= "^(?:(?:(?:(\\d+)-)?(\\d+):)?(\\d+):)?(\\d+)$"
        super(id, opts)
      end

      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        "text_field"
      end

      # Form label for this attribute
      # @param fmt [String, nil] formatting of form label
      # @return [String] form label
      def label(fmt: nil)
        (opts[:label] || "Time").to_s
      end
      
      def help(fmt: nil)
        (opts[:help] || "d-hh:mm:ss, or hh:mm:ss").to_s
      end
      
      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        # { script: { native: ["-t", value] } } would be the optimal here but the arrays in the
        # submission hash are not merged, submission needs to be handled in submit.yml.erb
        # { script: { wall_time: value } } could be set here to not need to use submit.yml.erb, but 
        # would require parsing the time into seconds here. Keeping it simple and consistent with 
        # the rest of the csc_ smart attributes for now
        {}
      end
    end
  end
end
