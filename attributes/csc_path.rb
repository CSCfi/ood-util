# Smart attribute for selecting path, can provide keyword(pre-defined method), method or raw value for paths in the form, allows renaming what the attribute is submitted as
# e.g.
# attributes:
#   csc_path:
#     submit: "notebook_dir"
#     paths:
#       - "HOME"
#       - "SCRATCH"
#       - "some_method"
#       - "/some/other/path"

module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCProject] the attribute object
    def self.build_csc_path(opts = {})
      # Allow overriding of smart attribute id
      id = opts[:submit].presence || "csc_path"
      Attributes::CSCPath.new(id, opts)
    end
  end

  module Attributes
    class CSCPath < Attribute

      def initialize(id, opts = {})
        @keywords = {
          :HOME => "get_home",
          :SCRATCH => "get_scratch",
          :PROJAPPL => "get_projappl"
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
        (opts[:label] || "Path").to_s
      end

      def parse_paths(paths)
        # Evaluate each path entry,
        # Flatten once to be able to generate multiple paths from one entry, e.g. all /scratch dirs
        paths.map do |path|
          eval_path = get_path(path)
        end.flatten(1)
      end

      # Evaluates the provided path entry
      def get_path(path)
        if @keywords.has_key?(path.to_sym)
          # Pre-defined methods (from keywords)
          send(@keywords[path.to_sym])
        elsif self.respond_to?(path)
          # Custom methods can be provided
          send(path)
        else
          # Raw path
          path
        end
      end

      def select_choices(*)
        paths = opts[:paths] || []
        # Cache per form
        @@select_choices ||= Hash.new do |h, key|
            h[key] = parse_paths(key)
        end
        @@select_choices[paths]
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

# Util methods for generating paths
# These might be moved to separate file in the future
module SmartAttributes
  module Attributes
    class CSCPath < Attribute
      def groups
        @groups ||= User.new.groups.map(&:name)
      end

      # User home directory
      def get_home
        Dir.home
      end

      # /scratch directories for all projects
      def get_scratch
        groups.map { |p| "/scratch/#{p}" if File.exist?("/scratch/#{p}")}.compact
      end

      # /projappl directories for all projects
      def get_projappl
        groups.map { |p| "/projappl/#{p}" if File.exist?("/projappl/#{p}")}.compact
      end
    end
  end
end
