require "minitest/autorun"
require "slurm_reservation"

class TestSlurmReservation < Minitest::Test

  def test_query_slurm
    assert_instance_of(String, SlurmReservation.query_slurm)
  end

  def test_parse_reservations
    assert_equal [], SlurmReservation.parse_reservations("")

    parsed = SlurmReservation.parse_reservations(@slurm_output)
    assert_equal 3, parsed.length
    assert_includes parsed, SlurmReservation::Reservation.new("test", ["r03c17"], "(null)", ["root", "robinkar"], [], ["SPEC_NODES"], [], "ACTIVE")
  end

  def test_available_reservations
    assert_equal [], SlurmReservation.available_reservations(@slurm_output, "unknownuser")
    reservations = SlurmReservation.available_reservations(@slurm_output, "robinkar")

    assert_equal 1, reservations.length
    assert_includes reservations, SlurmReservation::Reservation.new("test", ["r03c17"], "(null)", ["root", "robinkar"], [], ["SPEC_NODES"], [], "ACTIVE")
  end

  def test_parse_scontrol_arr
    assert_equal ["root", "user", "anotheruser"], SlurmReservation.parse_scontrol_arr("root,user,anotheruser")
    assert_equal [], SlurmReservation.parse_scontrol_arr("(null)")
    assert_equal ["user"], SlurmReservation.parse_scontrol_arr("user")
  end

  def test_parse_scontrol_show
    str = <<-EOF
    ReservationName=test Users=root,user,anotheruser Features=(null)
    ReservationName=anothertest
    EOF
    parsed = SlurmReservation.parse_scontrol_show(str)
    assert_includes parsed, {:ReservationName => "test", :Users => "root,user,anotheruser", :Features => "(null)"}
    assert_includes parsed, {:ReservationName => "anothertest"}
  end

  def setup
    @slurm_output = <<-EOF
ReservationName=test StartTime=2022-01-14T09:47:16 EndTime=2022-01-14T16:47:16 Duration=07:00:00 Nodes=r03c17 NodeCnt=1 CoreCnt=40 Features=(null) PartitionName=(null) Flags=SPEC_NODES TRES=cpu=40 Users=root,robinkar Groups=(null) Accounts=(null) Licenses=(null) State=ACTIVE BurstBuffer=(null) Watts=n/a MaxStartDelay=(null)
ReservationName=test StartTime=2022-01-14T09:47:16 EndTime=2022-01-14T16:47:16 Duration=07:00:00 Nodes=r03c[01-99] NodeCnt=1 CoreCnt=40 Features=(null) PartitionName=interactive Flags=SPEC_NODES TRES=cpu=40 Users=root Groups=(null) Accounts=(null) Licenses=(null) State=ACTIVE BurstBuffer=(null) Watts=n/a MaxStartDelay=(null)
ReservationName=inactivetest StartTime=2022-01-14T10:11:26 EndTime=2022-01-14T11:11:26 Duration=01:00:00 Nodes=r01g01 NodeCnt=1 CoreCnt=40 Features=(null) PartitionName=(null) Flags=SPEC_NODES TRES=cpu=40 Users=root,robinkar Groups=(null) Accounts=(null) Licenses=(null) State=INACTIVE BurstBuffer=(null) Watts=n/a MaxStartDelay=(null)
    EOF
  end
end
