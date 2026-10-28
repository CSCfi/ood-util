require "minitest/autorun"

require "slurm_partition_state"

class TestSlurmPartitionState < Minitest::Test

  def test_query_states
    assert_instance_of(String, SlurmPartitionState.query_states)
  end

  def test_usable_state
    [
      "idle", "mixed", "mixed-", "mix", "allocated", "alloc", "completing", "comp", "planned", "plnd",
      "blocked", "cloud", "resv", "reserved", "power_down", "powering_down", "powered_down", "powering_up",
      "reboot_issued", "reboot_requested", "idle~", "idle#", "idle!", "idle%", "idle@", "idle^", "mixed@",
      "some_new_state",
    ].each do |state|
      assert SlurmPartitionState.usable_state?(state), state
    end
    [
      "maint", "drain", "drain$", "drained", "draining", "drng", "down", "down*", "idle*", "idle$",
      "mixed*", "resv$", "reserved$", "fail", "failing", "future", "futr", "unk", "unknown", "inval", "no_respond",
    ].each do |state|
      refute SlurmPartitionState.usable_state?(state), state
    end
  end

  def test_parse_states_malformed
    assert_equal({}, SlurmPartitionState.parse_states(""))
    assert_equal({}, SlurmPartitionState.parse_states("sinfo: error: Unable to contact slurm controller\n"))
    assert_equal({}, SlurmPartitionState.parse_states("small|up|idle\n"))
    assert_equal({}, SlurmPartitionState.parse_states("small|up|idle|N/A\n"))
    assert SlurmPartitionState.parse_states("small|up|some_new_state|8\n")["small"][:available]
  end

  def test_parse_states
    assert_equal({}, SlurmPartitionState.parse_states(""))

    states = SlurmPartitionState.parse_states(@@slurm_output)
    assert_equal 5, states.length

    small = states["small"]
    assert_equal "small", small[:name]
    assert_equal "up", small[:avail]
    assert_equal 0, small[:usable]
    assert_equal 8, small[:total]
    assert_equal({"drain$" => 3, "maint" => 5}, small[:states])
    # Drained and maintenance nodes, nothing can run
    refute small[:available]

    # All nodes busy, jobs will start eventually
    assert states["large"][:available]
    assert_equal 100, states["large"][:usable]
    # Some idle nodes
    assert states["gpu"][:available]
    # Partition not up
    refute states["longrun"][:available]
    refute states["test"][:available]
  end

  @@slurm_output = <<-EOF
small|up|drain$|3
small|up|maint|5
large|up|allocated|90
large|up|mixed|10
large|up|down*|2
gpu|up|idle|2
gpu|up|drained|78
longrun|down|idle|12
test|drain|idle|2
  EOF
end
