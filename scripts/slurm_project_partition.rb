#
# This script fetches the project and partitions the user has access to from Slurm.
# Cached (memoized) for as long as the PUN is alive.
#

require 'open3'

module SlurmProjectPartition

  class << self

    # Runs a command with arguments passed to the capture2 call
    # Returns stdout or empty string on failure
    def run_command(*args)
      stdout_str, status = Open3.capture2(*args)
      return "" unless status.exitstatus == 0
      stdout_str
    rescue
      return ""
    end

    # Query slurm for project and partitions
    def query_slurm
      run_command("sacctmgr", "-p", "show", "-n", "assoc", "where", "user=#{ENV["USER"]}")
    end

    # Parse the slurm output into an array containing projects with an available partition
    # example [["project_1234", "interactive"], ["project_5678", "small"]]
    def parse_slurm_output(slurm_output)
      lines = slurm_output.strip.split("\n")
      lines.filter_map do |line|
        # take second and fourth column
        p_and_p = line.split("|").values_at(1,3)
        # filter out default_no_jobs
        p_and_p unless p_and_p[0] == "default_no_jobs"
      end.uniq
    end

    # Returns the list of projects from the slurm output
    # e.g. ["project_1234", "project_5678"]
    def get_projects(slurm_output)
      parsed = parse_slurm_output(slurm_output)
      # get only the first part(project) of the array, filter unique entries
      parsed.map do | p_and_p |
        p_and_p[0]
      end.uniq
    end

    # Cached version of the get_projects
    def projects
      @projects ||=
        begin
          get_projects(query_slurm)
        end
    end

    # Returns a list of projects from the slurm output and csc-projects output, includes names
    # e.g. [{:name => "project_2001659", :description => "CSC user's maintenance"}, {:name => "ood_installation", :description => "Puhti Open onDemand Environment Management"}]
    def get_projects_full(slurm_output, csc_projects_output)
      parsed = parse_slurm_output(slurm_output)
      project_names = parse_csc_projects(csc_projects_output)
      # get only the first part(project) of the array, filter unique entries
      parsed.map do | p_and_p |
        {:name => p_and_p[0], :description => project_names.fetch(p_and_p[0], p_and_p[0]) }
      end.uniq
    end

    # Cached version of the get_projects_full
    def projects_full
      @projects_full ||=
        begin
          get_projects_full(query_slurm, run_csc_projects)
        end
    end

    # Cached version of the get_projects_full, in the format for select_choices in smart_attributes
    def projects_full_for_smart_attribute
      @projects_full_for_smart_attribute ||=
        begin
          projects = projects_full
          projects.collect do |p|
            [p[:name], p[:name]]
          end
        end
    end

    # Returns a hash with the partitions as key and array of projects as values
    # example: {"interactive": ["project_1234", "project_5678"], "small": ["project_5678"]}
    def get_partitions(slurm_output)
      parsed = parse_slurm_output(slurm_output)
      # group the array into a hash where the partitions are keys and the project and partition array combinations are values
      grouped = parsed.group_by { | p_and_p| p_and_p[1] }
      # map the inner arrays to an array of projects
      grouped.map { |part, p_and_p| [part, p_and_p.map { |p| p[0] }] }.to_h
    end

    # Returns a hash with the partitions as key and array of projects that are not available for the partition
    # The format is as expected by OOD in the forms when using OOD_BC_DYNAMIC_JS
    # e.g. hides non-fmi partition when fmi project is selected
    # example: {"fmi": [{:"data-option-for-csc-slurm-project-project1234" => false}, {:"data-option-for-csc-slurm-project-project1234" => false}], ...}
    def get_partitions_with_data(slurm_output)
      parts = get_partitions(slurm_output)
      all_projects = get_projects(slurm_output)

      parts.transform_values do |projects|
        # select the project that are not allowed for this partition
        (all_projects - projects).map do |project|
          proj_name = project.gsub(/_/, '-')
          {"data-option-for-csc-slurm-project-#{proj_name}".to_sym => false}
        end
      end
    end

    # Cached version of get_partitions
    def partitions
      @partitions ||=
        begin
          get_partitions(query_slurm)
        end
    end

    def partitions_with_data
      @partitions_with_data ||=
        begin
          get_partitions_with_data(query_slurm)
        end
    end

    # Returns a hash where the keys are the project name and the description is the value
    # e.g. {"project_2001659"=>"CSC user's maintenance", "ood_installation"=>"Puhti Open onDemand Environment Management"}
    def parse_csc_projects(output)
      projects = output.lines.map { |line| line.strip.split(",", 2) }.to_h
      return projects
    end

    def run_csc_projects
      # Should probably have these paths somewhere else
      env = {"LD_LIBRARY_PATH" => "/ood/deps/lib:#{ENV["LD_LIBRARY_PATH"]}"}
      cmd = "/ood/deps/soft/csc-projects"
      # N = project name, T = Short description
      args = "--output=N,T"
      output = run_command(env, cmd, args)
      return output
    end
  end
end
