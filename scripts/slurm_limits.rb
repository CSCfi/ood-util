require 'open3'
require 'json'

module SlurmLimits

  # Structs for storing the results from slurm
  Job = Struct.new(:jobid, :acc, :part, :state)
  AssocLimit = Struct.new(:part, :acc, :maxjobs, :maxsubmit)
  QoSLimit = Struct.new(:name, :maxtres, :maxtrespa)
  Limit = Struct.new(:name, :time, :mem, :sct, :gres)

  # Parses command output into a Struct given as parameter
  def SlurmLimits.parse(output, struct, separator, limit = -1)
    lines = output.strip.split("\n")
    lines.map do |line|
      # Split the whole string but only take the needed amount of parameters
      struct.new(*(line.split(separator)[0..limit]))
    end
  end

  # Get the current amount of submits for an user per partition and project
  # returns a hash like {"project123_small" => 3}
  def SlurmLimits.submits
    begin
      begin
        stdout_str, status = Open3.capture2("squeue", "--noheader", "--format", "%i|%a|%P|%t", "--user", ENV["USER"])
        return {} unless status.exitstatus == 0
      rescue
        return {}
      end
      jobs = parse(stdout_str, Job, "|", 4)
      # return as hash with values like {"project123_interactive"=> 4}
      jobs.group_by { |job| "#{job[:acc]}_#{job[:part]}" }.transform_values { |part| part.length }
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

  # Gets QoS limits from slurm 
  def SlurmLimits.qos_limits
    @qos_limits ||= 
      begin
        begin
          stdout_str, status = Open3.capture2("sacctmgr", "--noheader", "-p", "show", "qos", "format=Name,MaxTres%100,MaxTresPA%200")
          return {} unless status.exitstatus == 0
        rescue
          return {}
        end
        limits = parse(stdout_str, QoSLimit, "|", 3)
        limits.map { |l| [l[:name], l.to_h] }.to_h
      end
  end

  # Get limits for partition type
  # returns a hash like {"small" => {:time => "3-00:00:00", :cores_max => 40, :mem => 373, "gres/gpu:v100" => 0, "gres/nvme": 3600} }
  def SlurmLimits.limits
    @limits ||=
      begin
        begin
          stdout_str, status = Open3.capture2("sinfo", "--noheader", "--format", "%R|%l|%m|%z|%G")
          return {} unless status.exitstatus == 0
        rescue
          return {}
        end
        parsed = parse(stdout_str, Limit, "|", 5).map { |p| populate_limit(p) }.group_by { |p| p[:name]}
        # parsed list contains multiple definitions for a partition, eg. node type M and IO, combine them
        parsed.transform_values { |p| combine_node_types(p) }
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

  # Parse a gres string like "gres/nvme:3600,gres/gpu:v100:4(S:0-1)"
  def SlurmLimits.parse_gres_string(gres)
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

  # Get limits from the qos definition
  def SlurmLimits.parse_qos(qos)
    limits = {}
    # Combine maxtre and maxtrespa
    unless qos[:maxtres].nil?
      qos[:maxtres].split(",") do |res|
        k, v = res.split("=")
        limits[k] = v.to_i
      end
    end
    # Get the smaller value if both of them define a limit
    unless qos[:maxtrespa].nil? 
      qos[:maxtrespa].split(",") do |res|
        k, v = res.split("=")
        unless limits.key?(k) && limits.fetch(k) < v.to_i
          limits[k] = v.to_i
        end
      end
    end
    #limits["cores_max"] = limits.delete("cpu") if limits.key?("cpu")
    limits
  end

  # Combines the different kinds of limits into one limit
  def SlurmLimits.populate_limit(limit)
    new_limits = limit.to_h

    # Convert limit to GB
    new_limits[:mem] = new_limits[:mem].to_i/1024

    # Multiply sockets * cores * threads for cpu value
    new_limits[:cpu] = new_limits[:sct].split(":").map {|v| v.to_i}.inject(:*)
    new_limits.delete(:sct)

    # Maximum gres values for the types
    new_limits.merge!(parse_gres_string(new_limits[:gres]))
    new_limits.delete(:gres)

    # Use QoS limit for gres if it exists, use lower value
    part_info = partitions.fetch(limit[:name], {})
    qos_name = part_info.fetch("QoS", "N/A")
    unless qos_name == "N/A"
      qos = qos_limits.fetch(qos_name, {})
      parsed_qos = parse_qos(qos)
      new_limits.merge!(parsed_qos){|key, old, new| [old, new].min }
    end
    new_limits
  end

  # Combine the possible node types eg. M, IO for a partition into one
  def SlurmLimits.combine_node_types(partition)
    max_partition = partition.inject{ |max_part, new_part| max_part.merge(new_part){|key,old,new| [old, new].max} }
    # If none of the node types specify nvme or gpu the limit is 0
    max_partition["gres/gpu:v100"] = max_partition.fetch("gres/gpu:v100", 0)
    max_partition["gres/nvme"] = max_partition.fetch("gres/nvme", 0)
    max_partition
  end
end
