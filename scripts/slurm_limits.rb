#
# This script fetches information about resource limits and maximum job submissions from Slurm
# Used in csc_slurm_limits smart attribute to provide form validation using form_validated.js
#
'''
Example output:

SlurmLimits.limits
{
  "small": {
    "name": "small", "time": "3-00:00:00", "mem": 373, "cpu": 40, "qos": {},
      "gres/nvme": 3600, "gres/gpu:v100": 0
  },
  "interactive": {
    "name": "interactive", "time": "7-00:00:00", "mem": 373, "cpu": 40,
    "qos": {
      "name": "interactive", "maxtres": {}, "maxtrespa": {},
      "maxtrespu": {
        "cpu": 8, "gres/nvme": 720, "mem": 76.0
      }
    },
    "gres/nvme": 3600, "gres/gpu:v100": 0
  }
}

SlurmLimits.assoc_limits
{
  "project_2002567_small": {
    "maxjobs": 200, "maxsubmit": 400
  },
  "project_2001659_interactive": {
    "maxjobs": 2, "maxsubmit": 2
  },
  "project_2001659_gpu": {
    "maxjobs": 200, "maxsubmit": 400
  }
}


SlurmLimits.running
[
  {
    "jobid": "12696087", "acc": "project_2001659", "part": "interactive", "state": "R",
    "tres": {
      "cpu": 4,
      "mem": 1.0,
      "gres/nvme": 1
    }
  },
  {
    "jobid": "12696151", "acc": "project_2001659", "part": "interactive", "state": "R",
    "tres": {
      "cpu": 4,
      "mem": 1.0,
      "gres/nvme": 1
    }
  }
]
'''
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
      # convert tres strings into hashes
      self.maxtres = SlurmLimits.parse_tres(maxtres)
      self.maxtrespa = SlurmLimits.parse_tres(maxtrespa)
      self.maxtrespu = SlurmLimits.parse_tres(maxtrespu)
    end
  end

  Limit = Struct.new(:name, :time, :mem, :cpu, :gres, :qos) do
    def initialize(*args)
      super(*args)
      self.mem = self.mem.to_i/1024
      # cpu is `S:C:T` (sockets:cores:threads), multiply to get max CPU
      self.cpu = self.cpu.split(":").map {|v| v.to_i}.inject(:*)
      self.gres = parse_gres_string(self.gres)
      self.qos = get_qos
    end

    def parse_gres_string(gres)
      # gres is either null or a comma separated list
      # e.g. `gpu:v100:4(S:0-1),nvme:3600`
      if gres == "(null)"
        return {}
      end
      gres_limits = {}
      unless gres == nil
        gres.split(",") do |res|
          if res.start_with?("nvme")
            # e.g. `nvme:3600`
            gres_limits["gres/nvme"] = res.split(":")[1].to_i
          elsif res.start_with?("gpu:")
            _, type, amount = res.split(":", 3)
            gres_limits["gres/gpu:#{type}"] = amount.to_i
          end
        end
      end
      gres_limits
    end

    def get_qos
      # Not all partitions have QoS set, look up which qos is set for the partition
      part_info = SlurmLimits.partitions.fetch(self.name, {})
      qos_name = part_info.fetch("QoS", "N/A")
      # Get MaxTres, MaxTresPA and MaxTresPU for the QoS
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
      # e.g.
      # `12695781|project_2001659|interactive|PD|cpu=1,mem=2G,node=1,billing=1,gres/nvme=4|`
      # `12695782|project_2001659|interactive|R|cpu=1,mem=2G,node=1,billing=1,gres/nvme=4|`
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
      # e.g.
      # |default_no_jobs|0|0
      # interactive|project_2001659|2|2
      # longrun|project_2001659|200|400
      run_command("sacctmgr", "--noheader", "--parsable2", "show", "assoc", "format=Partition,Account,MaxJobs,MaxSubmit", "where", "user=#{ENV["USER"]}")
    end

    def parse_assoc_limits(slurm_output)
      limits = parse(slurm_output, AssocLimit, "|", 4)
        .reject { |assoc| assoc[:acc] == "default_no_jobs" }
      # assoc limits are defined per project(account) and partition,
      # use a Hash with key `<project>_<partition>`
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
      # e.g.
      # normal|||
      # interactive|||cpu=8,gres/nvme=720,mem=76G
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
      # e.g.
      # test|15:00|190000|2:20:1|(null)
      # longrun|14-00:00:00|382000|2:20:1|nvme:3600
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
      # e.g.
      # PartitionName=small AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=YES QoS=N/A
      # PartitionName=large AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=accrue_large
      run_command("scontrol", "show", "partition", "--oneliner")
    end

    # Returns a Hash with partition names as keys and partition info (Hash) as values
    # e.g.
    # { "small": { "QoS": "N/A", "Nodes": "r01c[01-48],...", ... }, "large": ... }
    def parse_partitions(slurm_output)
      # slurm_output is in format `key=value key2=value2 ...`
      # one line per partition
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
    # Slurm automatically selects correct node type
    # e.g. max memory is 382000 and max nvme is 3600
    # interactive|7-00:00:00|382000|2:20:1|nvme:3600
    # interactive|7-00:00:00|190000|2:20:1|nvme:1490
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

    # Parse tres strings in running jobs and QoS limits to a Hash
    def parse_tres(tres)
      # QoS tres format: `cpu=8,gres/nvme=720,mem=76G`
      # running job tres format: `cpu=1,mem=2G,node=1,billing=1,gres/nvme=4`
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
