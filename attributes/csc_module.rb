# Smart attribute for selecting path, can provide path and filter to search, a method for searching modules, or just module names. paths and methods can be keyworded
# e.g.
# attributes:
#   csc_module:
#     submit: "course"
#     search:
#       - function: "get_jupyter_projappl_modules"
#       - path: "/appl/modulefiles/courses/"
#         filter: "Jupyter"
#       - path: "PRIVATEMODULES"
#         filter: ""
#       - module: "my_module"

require "pathname"
require "yaml"

module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCModule] the attribute object
    def self.build_csc_module(opts = {})
      # Allow overriding of smart attribute id
      id = opts[:submit].presence || "csc_module"
      Attributes::CSCModule.new(id, opts)
    end
  end

  module Attributes
    class CSCModule < Attribute

      def initialize(id, opts = {})
        @path_keywords = {
          :PRIVATEMODULES => CSCModules::PRIVATE_MODULES_DIR,
        }
        @fn_keywords = {
          :PROJECTMODULES => "get_project_modules",
        }
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
        (opts[:label] || "Module").to_s
      end

      def parse_search(search_params)
        # Evaluate each search entry,
        search_params.map do |search|
          eval_path = get_search(search)
        end.flatten(1)
      end

      # Evaluates the provided search entry
      def get_search(search_param)
        # Execute the function if a function was provided
        if search_param.has_key?(:function)
          # Keywords for common functions
          func = @fn_keywords.fetch(search_param[:function].to_sym, search_param[:function])
          if CSCModules.respond_to?(func)
            CSCModules.send(func).map(&:form_definition)
          else
            return []
          end
          # Search for modules in the path provided
        elsif search_param.has_key?(:path)
          # Keywords for common paths
          path = @path_keywords.fetch(search_param[:path].to_sym, search_param[:path])
          CSCModules.search_path(path, search_param[:filter])
        elsif search_param.has_key?(:module)
          return search_param[:module]
        else
          # Invalid format entered in form.yml.erb
          return []
        end
      end

      def select_choices(*)
        search = opts[:search] || []
        # Cache per form
        @@select_choices ||= Hash.new do |h, key|
          h[key] = parse_search(key)
        end
        @@select_choices[search]
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

