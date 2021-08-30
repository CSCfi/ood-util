require 'open3'
require 'json'

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
      gres.split(",") do |res|
        if res.start_with?("nvme")
          gres_limits["gres/nvme"] = res.split(":")[1].to_i
        elsif res.start_with?("gpu:v100")
          gres_limits["gres/gpu:v100"] = res.gsub(/gpu:v100:/, "").to_i
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

  # Parses command output into a Struct given as parameter
  def SlurmLimits.parse(output, struct, separator, limit = -1)
    lines = output.strip.split("\n")
    lines.map do |line|
      # Split the whole string but only take the needed amount of parameters
      struct.new(*(line.split(separator)[0..limit]))
    end
  end

  # Get the current amount of submits for an user per partition and project
  # returns an Array of running jobs, eg. [{"jobid" => "123456", "acc" => "project_123456", "part" => "interactive", "state" => "R", "tres" => {"cpu" => 2, "mem" => 2, "gres/nvme" => 32}, ... ]
  def SlurmLimits.running
    begin
      begin
        stdout_str, status = Open3.capture2("squeue", "--noheader", "--Format", "JobID:|,Account:|,Partition:|,StateCompact:|,tres-alloc:|", "--user", ENV["USER"])
        return {} unless status.exitstatus == 0
      rescue
        return {}
      end
      jobs = parse(stdout_str, Job, "|", 4)
      jobs
    end
  end

  # Get max jobs and submits per project and partition
  # returns a hash like {"project123_small" => {:maxjobs => 10, maxsubmit => 20}}
  def SlurmLimits.assoc_limits
    @assoc_limits ||= 
      begin
        begin
          stdout_str, status = Open3.capture2("sacctmgr", "--noheader", "-p", "show", "assoc", "format=Partition,Account,MaxJobs,MaxSubmit", "where", "user=#{ENV["USER"]}")
          return {} unless status.exitstatus == 0
        rescue
          return {}
        end
        # Skip default_no_jobs
        limits = parse(stdout_str, AssocLimit, "|", 4).reject { |assoc| assoc[:acc] == "default_no_jobs" }
        limits.map { |assoc| ["#{assoc[:acc]}_#{assoc[:part]}", {:maxjobs => assoc[:maxjobs].to_i, :maxsubmit => assoc[:maxsubmit].to_i}] }.to_h
      end
  end

  # Gets QoS limits from slurm,
  # eg. {:name=>"interactive", :maxtres=>{}, :maxtrespa=>{}, :maxtrespu=>{"cpu"=>8, "gres/nvme"=>720, "mem"=>76.0}}
  def SlurmLimits.qos_limits
    @qos_limits ||= 
      begin
        begin
          stdout_str, status = Open3.capture2("sacctmgr", "--noheader", "-p", "show", "qos", "format=Name,MaxTres,MaxTresPA,MaxTresPU")
          return {} unless status.exitstatus == 0
        rescue
          return {}
        end
        limits = parse(stdout_str, QoSLimit, "|", 4)
        limits.map { |l| [l[:name], l.to_h] }.to_h
      end
  end

  # Get limits for partition type
  # returns a hash like {"small" => {:time => "3-00:00:00", :cores_max => 40, :mem => 373, "gres/gpu:v100" => 0, "gres/nvme": 3600, :qos => {...}} }
  def SlurmLimits.limits
    @limits ||=
      begin
        begin
          stdout_str, status = Open3.capture2("sinfo", "--noheader", "--format", "%R|%l|%m|%z|%G")
          return {} unless status.exitstatus == 0
        rescue
          return {}
        end
        parsed = parse(stdout_str, Limit, "|", 5).group_by { |p| p[:name]}.transform_values { |p| combine_node_types(p.map(&:to_h))}
        # parsed list contains multiple definitions for a partition, eg. node type M and IO, combine them
        parsed
      end
  end

  # Get info about partition types, used for finding the related QoS limit for partition
  def SlurmLimits.partitions
    @partitions ||= 
      begin
        begin
          stdout_str, status = Open3.capture2("scontrol", "show", "partition", "-o")
          return {} unless status.exitstatus == 0
        rescue
          return {}
        end
        # Different format than the rest of the slurm commands
        lines = stdout_str.strip.split("\n")
        lines.map do |line|
          part = {}
          line.split(" ") do |entry| 
            k, v = entry.split("=")
            part[k] = v
          end
          [part.fetch("PartitionName", "unknown"), part]
        end.to_h
      end
  end

  # Combine the possible node types eg. M, IO for a partition into one
  def SlurmLimits.combine_node_types(partition)
    max_partition = partition.inject{ |max_part, new_part| max_part.deep_merge(new_part){|key,old,new| [old, new].max} }
    max_partition.merge!(max_partition.delete(:gres))
    # If none of the node types specify nvme or gpu the limit is 0
    max_partition["gres/gpu:v100"] = max_partition.fetch("gres/gpu:v100", 0)
    max_partition["gres/nvme"] = max_partition.fetch("gres/nvme", 0)
    max_partition
  end

  def SlurmLimits.parse_tres(tres)
    return {} if tres.nil?

    tres.split(",").filter_map { |r|
      res, value = r.split("=")
      if res == "mem"
        suffix = value[-1]
        value = case suffix
                when "M"
                  value.to_f/1024.0
                when "G"
                  value.to_f
                when "T"
                  value.to_f*1024.0
                else
                  value.to_f/1024.0
                end
      else
        value = value.to_i
      end
      [res, value] unless res == "node" || res == "billing"
    }.to_h
  end

end
