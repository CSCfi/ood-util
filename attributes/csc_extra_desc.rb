module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCExtraDesc] the attribute object
    def self.build_csc_extra_desc(opts = {})
      Attributes::CSCExtraDesc.new("csc_extra_desc", opts)
    end
  end

  module Attributes
    class CSCExtraDesc < Attribute
      def initialize(id, opts = {})
        opts[:class] ||= "d-none"
        opts[:skip_label] ||= true
        opts[:help] ||= opts[:desc]
        super(id, opts)
      end
      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        "text_field"
      end

      def submit(fmt: nil)
        {}
      end
    end
  end
end
