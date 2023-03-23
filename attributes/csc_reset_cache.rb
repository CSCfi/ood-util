# This SmartAttribute must be used together with form_validated.js
# This only adds a hidden form element, which then is detected
# by the JavaScript, which adds a new button to the page
# Usage in form.yml:
# attributes:
#   csc_reset_cache:
#     app: sys/ood-base-jupyter
# form:
#   - csc_reset_cache
#
module SmartAttributes
  class AttributeFactory
    def self.build_csc_reset_cache(opts = {})
      Attributes::CSCResetCache.new("csc_reset_cache", opts)
    end
  end

  module Attributes
    class CSCResetCache < Attribute

      def initialize(id, opts={})
        # Some simple validation for app name
        if opts.has_key?(:app) && opts[:app].match(/^(?:dev|sys|usr)\/.+$/)
          cache_file = "#{opts.delete(:app).gsub('/', '_')}.json"
          opts[:data] = {:app => BatchConnect::Session.cache_root.join(cache_file).to_s}
        end
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
