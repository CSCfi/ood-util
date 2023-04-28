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
          :PRIVATEMODULES => "#{Dir.home}/privatemodules",
        }
        @fn_keywords = {
          :PROJECTMODULES => "get_project_modules",
        }
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
          if self.respond_to?(func)
            send(func)
          else
            return []
          end
          # Search for modules in the path provided
        elsif search_param.has_key?(:path)
          # Keywords for common paths
          path = @path_keywords.fetch(search_param[:path].to_sym, search_param[:path])
          search_path(path, search_param[:filter])
        elsif search_param.has_key?(:module)
          return search_param[:module]
        else
          # Invalid format entered in form.yml.erb
          return []
        end
      end

      # Searches a path for modules, filters for string in the file
      # same as
      # cd <path> && grep -l <filter> *.lua | cut -d "." -f1
      def search_path(path, filter="")
        path = path.chomp("/")
        filter = "" if filter.nil?

        # expand *.lua for grep
        files = Dir.glob("#{path}/*.lua")
        stdout_str, status = Open3.capture2("grep", "-l", filter, *files)
        # No files found/exist
        return [] unless status.success?
        # Return only module names
        stdout_str.split.map { |p| Pathname.new(p).basename(".lua").to_s }
      end

      def select_choices
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

# Util methods for generating paths
# These might be moved to separate file in the future
module SmartAttributes
  module Attributes
    class CSCModule < Attribute
      def groups
        @groups ||= User.new.groups.map(&:name)
      end

      def get_project_modules
        modules = groups.map do |p|
          search_path("/projappl/#{p}/www_#{ENV["CSC_CLUSTER"]}_modules").map do |name|
            [name, name, {"data-project".to_sym => p}]
          end
        end.flatten(1)
        modules
      end

      # Searches path for modules containing "Jupyter", can include the name of the directory or not
      def get_jupyter_modules(path, test: false, project: nil, include_dir: true)
        search_path(path, "Jupyter").map do |name|
          res = get_resources(path, name)
          # Hide module when other projects are selected
          other_projects_data = (groups-[project]).map { |p| {"data-option-for-csc-slurm-project-#{p.gsub(/_/, "-")}".to_sym => false} } unless project.nil?

          # Include directory if it is not a private or project module
          dir = Pathname.new(path).basename
          val = include_dir ? "#{dir}/#{name}" : name
          val = "#{project}/#{val}" unless project.nil?

          # option for dropdown, set resources and extra data
          [
            name,
            val,
            {
              "data-set-csc-cores".to_sym => res["cores"],
              "data-set-csc-time".to_sym => res["time"],
              "data-set-csc-memory".to_sym => (res["mem"].to_i.to_s unless res["mem"].nil?),
              "data-set-csc-nvme".to_sym => res["local_disk"],
              "data-set-csc-slurm-partition".to_sym => res["partition"],
              "data-test".to_sym => test,
              "data-project".to_sym => project}.compact,
              *other_projects_data
          ]
        end
      end

      # Read the resource file for a module in the specified path, for course Jupyter app
      def get_resources(path, mod)
        # e.g. {"cores"=>1, "time"=>"02:00:00", "partition"=>"interactive", "local_disk"=>0, "mem"=>"4GB"}
        YAML.load_file("#{path.chomp("/")}/#{mod}-resources.yml")
      rescue => e
        {}
      end

      # Get CSC course modules containing Jupyter
      def get_jupyter_course_modules
        get_jupyter_modules("/appl/modulefiles/courses")
      end

      # Get modules containing "Jupyter" for all projects
      def get_jupyter_projappl_modules
        modules = groups.map do |p|
          get_jupyter_modules("/projappl/#{p}/www_#{ENV["CSC_CLUSTER"]}_modules", project: p)
        end.flatten(1)
        modules
      end

      # Get test/private modules
      def get_jupyter_private_modules
        get_jupyter_modules(@path_keywords[:PRIVATEMODULES], test: true)
      end
    end
  end
end
