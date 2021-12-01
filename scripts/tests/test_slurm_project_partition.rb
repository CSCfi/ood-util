require "minitest/autorun"
require "slurm_project_partition"

class TestSlurmProjectPartition < Minitest::Test

  def test_query_slurm
    assert_instance_of(String, SlurmProjectPartition.query_slurm)
  end

  def test_parse_slurm_output
    assert_equal [], SlurmProjectPartition.parse_slurm_output("")

    parsed = SlurmProjectPartition.parse_slurm_output(@slurm_output)

    assert_equal 29, parsed.length
    assert_equal ["ood_installation", "interactive"], parsed.first
    assert_includes parsed, ["project_2001659", "gpu"]
    assert_includes parsed, ["project_2002037", "fmi"]
  end

  def test_get_projects
    projects = SlurmProjectPartition.get_projects(@slurm_output)

    assert_equal 4, projects.length
    assert_equal "ood_installation", projects.first
    assert_includes projects, "project_2002567"
  end

  def test_partitions
    partitions = SlurmProjectPartition.get_partitions(@slurm_output)

    assert_equal 11, partitions.length

    interactive = partitions["interactive"]
    assert_equal ["ood_installation", "project_2002567", "project_2001659"], interactive

    fmi = partitions["fmi"]
    assert_equal ["project_2002037"], fmi
  end

  def setup
    @slurm_output = <<-EOF
puhti|ood_installation|robinkar|interactive|1|||||||2|||2|||normal|||
puhti|ood_installation|robinkar|longrun|1|||||||200|||400|||normal|||
puhti|ood_installation|robinkar|gpu|1|||gres/gpu:v100=160||||200|||400|||normal|||
puhti|ood_installation|robinkar|small|1|||||||200|||400|||normal|||
puhti|ood_installation|robinkar|test|1|||||||1|||2|||normal|||
puhti|ood_installation|robinkar|large|1|||||||200|||400|||normal|||
puhti|ood_installation|robinkar|hugemem_longrun|1|||||||200|||400|||normal|||
puhti|ood_installation|robinkar|gputest|1|||gres/gpu:v100=8||||1|||2|||normal|||
puhti|ood_installation|robinkar|hugemem|1|||||||200|||400|||normal|||
puhti|project_2002567|robinkar|interactive|1|||||||2|||2|||normal|||
puhti|project_2002567|robinkar|longrun|1|||||||200|||400|||normal|||
puhti|project_2002567|robinkar|gpu|1|||gres/gpu:v100=160||||200|||400|||normal|||
puhti|project_2002567|robinkar|small|1|||||||200|||400|||normal|||
puhti|project_2002567|robinkar|test|1|||||||1|||2|||normal|||
puhti|project_2002567|robinkar|large|1|||||||200|||400|||normal|||
puhti|project_2002567|robinkar|hugemem_longrun|1|||||||200|||400|||normal|||
puhti|project_2002567|robinkar|gputest|1|||gres/gpu:v100=8||||1|||2|||normal|||
puhti|project_2002567|robinkar|hugemem|1|||||||200|||400|||normal|||
puhti|default_no_jobs|robinkar||1|||||||0|||0|||normal|||
puhti|project_2001659|robinkar|interactive|1|||||||2|||2|||normal|||
puhti|project_2001659|robinkar|longrun|1|||||||200|||400|||normal|||
puhti|project_2001659|robinkar|gpu|1|||gres/gpu:v100=160||||200|||400|||normal|||
puhti|project_2001659|robinkar|small|1|||||||200|||400|||normal|||
puhti|project_2001659|robinkar|test|1|||||||1|||2|||normal|||
puhti|project_2001659|robinkar|large|1|||||||200|||400|||normal|||
puhti|project_2001659|robinkar|hugemem_longrun|1|||||||200|||400|||normal|||
puhti|project_2001659|robinkar|gputest|1|||gres/gpu:v100=8||||1|||2|||normal|||
puhti|project_2001659|robinkar|hugemem|1|||||||200|||400|||normal|||
puhti|project_2002037|nortamoh|fmi|1|||||||200|||400|||normal|||
puhti|project_2002037|nortamoh|fmitest|1|||||||2|||4|||normal|||
    EOF
  end

end
