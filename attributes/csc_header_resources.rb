module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCExtraDesc] the attribute object
    def self.build_csc_header_resources(opts = {})
      Attributes::CSCResourcesHeader.new("csc_header_resources", opts)
    end
  end

  module Attributes
    class CSCResourcesHeader < Attribute
      def initialize(id, opts = {})
        opts[:class] ||= "d-none"
        opts[:skip_label] ||= true
        opts[:content] ||= "---\n### Resources"
        opts[:help] ||= opts[:content]
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

