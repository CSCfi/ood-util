require "minitest/autorun"
require "slurm_limits"

class TestSlurmLimits < Minitest::Test

  # Running jobs
  def test_query_running
    assert_instance_of(String, SlurmLimits.query_running)
  end

  def test_parse_running
    assert_equal [], SlurmLimits.parse_running("")

    running = SlurmLimits.parse_running(@@slurm_output_running)
    assert_equal 2, running.length

    first = running.first
    assert_equal "9432889", first.jobid
    assert_equal "ood_installation", first.acc
    assert_equal "interactive", first.part
    assert_equal "R", first.state
  end

  # Assoc limits
  def test_query_assoc_limits
    assert_instance_of(String, SlurmLimits.query_assoc_limits)
  end

  def test_parse_assoc_limits
    assert_equal({}, SlurmLimits.parse_assoc_limits(""))

    limits = SlurmLimits.parse_assoc_limits(@@slurm_output_assoc_limits)
    assert_equal 27, limits.length

    l = limits["project_2001659_test"]
    assert_equal 1, l[:maxjobs]
    assert_equal 2, l[:maxsubmit]
  end

  # QoS limits
  def test_query_qos_limits
    assert_instance_of(String, SlurmLimits.query_qos_limits)
  end

  def test_parse_qos_limits
    assert_equal({}, SlurmLimits.parse_qos_limits(""))

    limits = SlurmLimits.parse_qos_limits(@@slurm_output_qos_limits)
    assert_equal 7, limits.length

    interactive = limits["interactive"]
    assert_equal "interactive", interactive[:name]
    assert_equal({}, interactive[:maxtres])
    assert_equal({}, interactive[:maxtrespa])
    assert_equal({"cpu" => 8, "gres/nvme"=>720, "mem"=>76.0}, interactive[:maxtrespu])

    gpu = limits["gputres_accrue"]
    assert_equal "gputres_accrue", gpu[:name]
    assert_equal({"gres/gpu:v100"=>80}, gpu[:maxtrespa])
  end

  ## Limits
  def test_query_limits
    assert_instance_of(String, SlurmLimits.query_limits)
  end

  def test_parse_limits
    SlurmLimits.stub :query_partitions, @@slurm_output_partitions do
      SlurmLimits.stub :query_qos_limits, "" do
        assert_equal({}, SlurmLimits.parse_limits(""))
        limits = SlurmLimits.parse_limits(@@slurm_output_limits)
        assert_equal 12, limits.length

        interactive = limits["interactive"]
        assert_equal "interactive", interactive[:name]
        assert_equal("7-00:00:00", interactive[:time])
        assert_equal(373, interactive[:mem])
        assert_equal(40, interactive[:cpu])
        assert_equal({}, interactive[:qos])
        assert_equal(0, interactive["gres/gpu:v100"])
        assert_equal(3600, interactive["gres/nvme"])

        interactive_mahti = limits["interactive_mahti"]
        assert_equal(256, interactive_mahti[:cpu])
        assert_equal(1875/1024.0, interactive_mahti[:max_mem_per_cpu])

        gpu = limits["gpu"]
        assert_equal 4, gpu["gres/gpu:v100"]
        assert_equal 3600, gpu["gres/nvme"]

        # Small can be on both IO nodes and non-IO nodes with different limits
        small = limits["small"]
        assert_equal 373, gpu[:mem]
        assert_equal 3600, gpu["gres/nvme"]

        test = limits["test"]
        assert_equal "15:00", test[:time]

        gpu_s = limits["gpusmall"]
        assert_equal 4, gpu_s["gres/gpu:a100"]
        assert_equal 3500, gpu_s["gres/nvme"]

        gpu_m = limits["gpumedium"]
        assert_equal 4, gpu_m["gres/gpu:a100"]
        assert_equal 3500, gpu_s["gres/nvme"]
      end
    end
  end

  # Partitions
  def test_query_partitions
    assert_instance_of(String, SlurmLimits.query_partitions)
  end

  def test_parse_partitions
    assert_equal({}, SlurmLimits.parse_partitions(""))

    partitions = SlurmLimits.parse_partitions(@@slurm_output_partitions)
    assert_equal 10, partitions.length

    assert_equal "interactive", partitions["interactive"]["QoS"]
    assert_equal "gputres_accrue", partitions["gpu"]["QoS"]
    assert_equal "N/A", partitions["small"]["QoS"]
  end

  def test_parse_tres
    tres = SlurmLimits.parse_tres("")
    assert_equal({}, tres)

    tres = SlurmLimits.parse_tres("cpu=40,mem=80G,node=1,billing=40")
    assert_equal 40, tres["cpu"]
    assert_equal 80, tres["mem"]
    assert_nil tres["node"]
    assert_nil tres["billing"]

    tres = SlurmLimits.parse_tres("cpu=1,mem=1250M,node=1,billing=1,gres/nvme=16")
    assert_equal 1, tres["cpu"]
    assert_in_epsilon 1.2207, tres["mem"]
    assert_equal 16, tres["gres/nvme"]

    tres = SlurmLimits.parse_tres("cpu=2,mem=382000M,node=1,billing=2,gres/gpu:v100=4,gres/nvme=3600")
    assert_equal 2, tres["cpu"]
    assert_in_epsilon 373, tres["mem"]
    assert_equal 4, tres["gres/gpu:v100"]
    assert_equal 3600, tres["gres/nvme"]
  end

  # Test data
  @@slurm_output_running = <<-EOF
9432889|ood_installation|interactive|R|cpu=1,mem=1G,node=1,billing=1|
9432885|project_2001659|small|R|cpu=1,mem=2G,node=1,billing=1,gres/nvme=10|
  EOF
  @@slurm_output_assoc_limits = <<-EOF
interactive|ood_installation|2|2|
longrun|ood_installation|200|400|
gpu|ood_installation|200|400|
small|ood_installation|200|400|
test|ood_installation|1|2|
large|ood_installation|200|400|
hugemem_longrun|ood_installation|200|400|
gputest|ood_installation|1|2|
hugemem|ood_installation|200|400|
interactive|project_2002567|2|2|
longrun|project_2002567|200|400|
gpu|project_2002567|200|400|
small|project_2002567|200|400|
test|project_2002567|1|2|
large|project_2002567|200|400|
hugemem_longrun|project_2002567|200|400|
gputest|project_2002567|1|2|
hugemem|project_2002567|200|400|
|default_no_jobs|0|0|
interactive|project_2001659|2|2|
longrun|project_2001659|200|400|
gpu|project_2001659|200|400|
small|project_2001659|200|400|
test|project_2001659|1|2|
large|project_2001659|200|400|
hugemem_longrun|project_2001659|200|400|
gputest|project_2001659|1|2|
hugemem|project_2001659|200|400|
  EOF
  @@slurm_output_qos_limits = <<-EOF
normal||||
longrun||||
hugemem_longrun||||
accrue_large||||
interactive|||cpu=8,gres/nvme=720,mem=76G|
gputres_accrue||gres/gpu:v100=80||
interactive_mahti|||cpu=64
  EOF

  @@slurm_output_limits = <<-EOF
small|3-00:00:00|190000+|2:20:1|(null)
small|3-00:00:00|382000|2:20:1|nvme:3600
large|3-00:00:00|190000+|2:20:1|(null)
large|3-00:00:00|382000|2:20:1|nvme:3600
test|15:00|190000|2:20:1|(null)
longrun|14-00:00:00|190000+|2:20:1|(null)
longrun|14-00:00:00|382000|2:20:1|nvme:3600
hugemem|3-00:00:00|764000+|2:20:1|(null)
hugemem_longrun|7-00:00:00|764000+|2:20:1|(null)
gputest|15:00|382000|2:20:1|gpu:v100:4(S:0-1),nvme:3600
gpu|3-00:00:00|382000|2:20:1|gpu:v100:4(S:0-1),nvme:3600
interactive|7-00:00:00|382000|2:20:1|nvme:3600
gpusmall|1-12:00:00|490000|4:32:2|gpu:a100:4(S:0-1),nvme:3500
gpumedium|1-12:00:00|490000|4:32:2|gpu:a100:4,nvme:3500
interactive_mahti|7-00:00:00|240000|8:16:2|(null)
  EOF

  @@slurm_output_partitions = <<-EOF
PartitionName=small AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=YES QoS=N/A DefaultTime=00:10:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=1 MaxTime=3-00:00:00 MinNodes=0 LLN=NO MaxCPUsPerNode=UNLIMITED Nodes=r01c[01-48],r02c[01-48],r03c[01-48],r04c[01-48],r13c[01-48],r14c[01-48],r15c[01-48],r16c[01-48],r17c[01-48],r18c[01-48],r05c[01-64],r06c[01-64],r07c[07-48,53-56] PriorityJobFactor=10 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=26160 TotalNodes=654 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerNode=UNLIMITED MaxMemPerNode=UNLIMITED
PartitionName=large AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=accrue_large DefaultTime=00:10:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=26 MaxTime=3-00:00:00 MinNodes=2 LLN=NO MaxCPUsPerNode=UNLIMITED Nodes=r01c[01-48],r02c[01-48],r03c[01-48],r04c[01-48],r13c[01-48],r14c[01-48],r15c[01-48],r16c[01-48],r17c[01-48],r18c[01-48],r05c[01-64],r06c[01-64],r07c[07-48,53-56] PriorityJobFactor=10 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=26160 TotalNodes=654 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerNode=UNLIMITED MaxMemPerNode=UNLIMITED
PartitionName=test AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=N/A DefaultTime=00:05:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=2 MaxTime=00:15:00 MinNodes=0 LLN=NO MaxCPUsPerNode=UNLIMITED Nodes=r07c[01-06] PriorityJobFactor=50 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=240 TotalNodes=6 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerNode=UNLIMITED MaxMemPerNode=UNLIMITED
PartitionName=longrun AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=longrun DefaultTime=00:10:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=1 MaxTime=14-00:00:00 MinNodes=0 LLN=NO MaxCPUsPerNode=UNLIMITED Nodes=r01c[01-48],r02c[01-48],r03c[01-48],r04c[01-48],r13c[01-48],r14c[01-48],r15c[01-48],r16c[01-48],r17c[01-48],r18c[01-48],r05c[01-64],r06c[01-64],r07c[07-48,53-56] PriorityJobFactor=9 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=26160 TotalNodes=654 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerNode=UNLIMITED MaxMemPerNode=UNLIMITED
PartitionName=hugemem AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=N/A DefaultTime=00:10:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=4 MaxTime=3-00:00:00 MinNodes=0 LLN=NO MaxCPUsPerNode=UNLIMITED Nodes=r08m[01-06],r07c[57-68] PriorityJobFactor=10 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=720 TotalNodes=18 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerNode=UNLIMITED MaxMemPerNode=UNLIMITED
PartitionName=hugemem_longrun AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=hugemem_longrun DefaultTime=00:10:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=1 MaxTime=7-00:00:00 MinNodes=0 LLN=NO MaxCPUsPerNode=UNLIMITED Nodes=r08m[01-06],r07c[57-68] PriorityJobFactor=9 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=720 TotalNodes=18 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerNode=UNLIMITED MaxMemPerNode=UNLIMITED
PartitionName=gputest AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=N/A DefaultTime=00:05:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=2 MaxTime=00:15:00 MinNodes=0 LLN=NO MaxCPUsPerNode=UNLIMITED Nodes=r01g01,r02g01 PriorityJobFactor=50 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=80 TotalNodes=2 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerNode=UNLIMITED MaxMemPerNode=UNLIMITED
PartitionName=gpu AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=gputres_accrue DefaultTime=00:10:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=20 MaxTime=3-00:00:00 MinNodes=0 LLN=NO MaxCPUsPerNode=UNLIMITED Nodes=r01g[02-08],r02g[02-08],r03g[01-08],r04g[01-08],r13g[01-08],r14g[01-08],r15g[01-08],r16g[01-08],r17g[01-08],r18g[01-08] PriorityJobFactor=10 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=3120 TotalNodes=78 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerNode=UNLIMITED MaxMemPerNode=UNLIMITED
PartitionName=interactive AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=interactive DefaultTime=1-00:00:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=1 MaxTime=7-00:00:00 MinNodes=0 LLN=YES MaxCPUsPerNode=UNLIMITED Nodes=r07c[49-52] PriorityJobFactor=50 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=160 TotalNodes=4 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerNode=UNLIMITED MaxMemPerNode=UNLIMITED
PartitionName=interactive_mahti AllowGroups=ALL AllowAccounts=ALL AllowQos=ALL AllocNodes=ALL Default=NO QoS=interactive DefaultTime=1-00:00:00 DisableRootJobs=YES ExclusiveUser=NO GraceTime=0 Hidden=NO MaxNodes=1 MaxTime=7-00:00:00 MinNodes=0 LLN=YES MaxCPUsPerNode=UNLIMITED Nodes=c[3101-3104,4101-4104] PriorityJobFactor=50 PriorityTier=1 RootOnly=NO ReqResv=NO OverSubscribe=NO OverTimeLimit=NONE PreemptMode=OFF State=UP TotalCPUs=2048 TotalNodes=8 SelectTypeParameters=NONE JobDefaults=(null) DefMemPerCPU=1875 MaxMemPerCPU=1875 TRES=cpu=2048,mem=1875G,node=8,billing=2048
  EOF
end
