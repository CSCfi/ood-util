#
# This script fetches information about resource limits and maximum job submissions from Slurm
# Used in csc_slurm_limits smart attribute to provide form validation using form_validated.js
#

require 'open3'
require 'json'
require 'active_support'

module SlurmLimits

  # Structs for storing the results from slurm
  Job = Struct.new(:jobid, :acc, :part, :state, :tres) do
    def initialize(*args)
      super(*args)
      self.tres = SlurmLimits.parse_tres(tres)
    end
  end

  AssocLimit = Struct.new(:part, :acc, :maxjobs, :maxsubmit)
  QoSLimit = Struct.new(:name, :maxtres, :maxtrespa, :maxtrespu) do
    def initialize(*args)
      super(*args)
      self.maxtres = SlurmLimits.parse_tres(maxtres)
      self.maxtrespa = SlurmLimits.parse_tres(maxtrespa)
      self.maxtrespu = SlurmLimits.parse_tres(maxtrespu)
    end
  end

  Limit = Struct.new(:name, :time, :mem, :cpu, :gres, :qos) do
    def initialize(*args)
      super(*args)
      self.mem = self.mem.to_i/1024
      self.cpu = self.cpu.split(":").map {|v| v.to_i}.inject(:*)
      self.gres = parse_gres_string(self.gres)
      self.qos = get_qos
    end

    def parse_gres_string(gres)
      if gres == "(null)"
        return {}
      end
      gres_limits = {}
      unless gres == nil
        gres.split(",") do |res|
          if res.start_with?("nvme")
            gres_limits["gres/nvme"] = res.split(":")[1].to_i
          elsif res.start_with?("gpu:v100") # TODO: support other GPU types
            gres_limits["gres/gpu:v100"] = res.gsub(/gpu:v100:/, "").to_i
          end
        end
      end
      gres_limits
    end

    def get_qos
      part_info = SlurmLimits.partitions.fetch(self.name, {})
      qos_name = part_info.fetch("QoS", "N/A")
      SlurmLimits.qos_limits.fetch(qos_name, {})
    end
  end

  class << self
    # Parses command output into a Struct given as parameter
    def parse(output, struct, separator, limit = -1)
      lines = output.strip.split("\n")
      lines.map do |line|
        # Split the whole string but only take the needed amount of parameters
        struct.new(*(line.split(separator)[0..limit]))
      end
    end


    # Runs the specified command
    # Commandline arguments separated into parameters (normal Open3.capture2 usage)
    def run_command(*args)
      stdout_str, status = Open3.capture2(*args)
      return "" unless status.exitstatus == 0
      stdout_str
    rescue
      return ""
    end


    # Get the current amount of submits for an user per partition and project
    # returns an Array of running jobs, eg. [{"jobid" => "123456", "acc" => "project_123456", "part" => "interactive", "state" => "R", "tres" => {"cpu" => 2, "mem" => 2, "gres/nvme" => 32}, ... ]
    def running
      slurm_output = query_running
      parse_running(slurm_output)
    end

    def query_running
      run_command("squeue", "--noheader", "--Format", "JobID:|,Account:|,Partition:|,StateCompact:|,tres-alloc:|", "--user", ENV["USER"])
    end

    def parse_running(slurm_output)
      parse(slurm_output, Job, "|", 4)
    end


    # Get max jobs and submits per project and partition
    # returns a hash like {"project123_small" => {:maxjobs => 10, maxsubmit => 20}}
    def assoc_limits
      @assoc_limits ||=
        begin
          slurm_output = query_assoc_limits
          parse_assoc_limits(slurm_output)
        end
    end

    def query_assoc_limits
      run_command("sacctmgr", "--noheader", "--parsable2", "show", "assoc", "format=Partition,Account,MaxJobs,MaxSubmit", "where", "user=#{ENV["USER"]}")
    end

    def parse_assoc_limits(slurm_output)
      limits = parse(slurm_output, AssocLimit, "|", 4)
        .reject { |assoc| assoc[:acc] == "default_no_jobs" }
      limits.map do |assoc|
        k = "#{assoc[:acc]}_#{assoc[:part]}"
        v = {:maxjobs => assoc[:maxjobs].to_i, :maxsubmit => assoc[:maxsubmit].to_i}
        [k, v]
      end.to_h
    end


    # Gets QoS limits from slurm,
    # eg. {:name=>"interactive", :maxtres=>{}, :maxtrespa=>{}, :maxtrespu=>{"cpu"=>8, "gres/nvme"=>720, "mem"=>76.0}}
    def qos_limits
      @qos_limits ||=
        begin
          slurm_output = query_qos_limits
          parse_qos_limits(slurm_output)
        end
    end

    def query_qos_limits
      run_command("sacctmgr", "--noheader", "--parsable2", "show", "qos", "format=Name,MaxTres,MaxTresPA,MaxTresPU")
    end

    def parse_qos_limits(slurm_output)
      limits = parse(slurm_output, QoSLimit, "|", 4)
      limits.map { |l| [l[:name], l.to_h] }.to_h
    end


    # Get limits for partition type
    # returns a hash like {"small" => {:time => "3-00:00:00", :cores_max => 40, :mem => 373, "gres/gpu:v100" => 0, "gres/nvme": 3600, :qos => {...}} }
    def limits
      @limits ||=
        begin
          slurm_output = query_limits
          parse_limits(slurm_output)
        end
    end

    def query_limits
      run_command("sinfo", "--noheader", "--Format", "PartitionName:|,Time:|,Memory:|,SocketCoreThread:|,Gres:")
    end

    def parse_limits(slurm_output)
      parsed = parse(slurm_output, Limit, "|", 5)
        .group_by { |p| p[:name]}
        .transform_values { |p| combine_node_types(p.map(&:to_h))}
      # parsed list contains multiple definitions for a partition, eg. node type M and IO, combine them
      parsed
    end


    # Get info about partition types, used for finding the related QoS limit for partition
    def partitions
      @partitions ||=
        begin
          slurm_output = query_partitions
          parse_partitions(slurm_output)
        end
    end

    def query_partitions
      run_command("scontrol", "show", "partition", "--oneliner")
    end

    def parse_partitions(slurm_output)
      lines = slurm_output.strip.split("\n")
      lines.map do |line|
        part = {}
        line.split(" ") do |entry|
          k, v = entry.split("=")
          part[k] = v
        end
        [part.fetch("PartitionName", "unknown"), part]
      end.to_h
    end

    # Combine the possible node types eg. M, IO for a partition into one
    def combine_node_types(partition)
      max_partition = partition
        .inject{ |max_part, new_part| max_part
        .deep_merge(new_part){|key,old,new| [old, new].max} }
      max_partition.merge!(max_partition.delete(:gres))
      # If none of the node types specify nvme or gpu the limit is 0
      max_partition["gres/gpu:v100"] = max_partition.fetch("gres/gpu:v100", 0)
      max_partition["gres/nvme"] = max_partition.fetch("gres/nvme", 0)
      max_partition
    end

    def parse_tres(tres)
      return {} if tres.nil?
      tres.split(",").filter_map do |r|
        res, value = r.split("=")
        value = if res == "mem"
          convert_mem_to_g(value)
        else
          value.to_i
        end
        [res, value] unless res == "node" || res == "billing"
      end.to_h
    end

    # Converts Slurm memory strings into GB (float) (e.g 2048M to 2.0G)
    def convert_mem_to_g(str)
      suffix = str[-1]
      value = case suffix
              when "M"
                str.to_f/1024.0
              when "G"
                str.to_f
              when "T"
                str.to_f*1024.0
              else
                str.to_f/1024.0
              end
      value
    end
  end
end
