require "open3"

module SlurmReservation

  Reservation = Struct.new(:name, :nodes, :partition_name, :users, :groups, :flags, :accounts, :state) do
    def can_use(user, user_groups)
      if state != "ACTIVE"
        return false
      end
      if !users.empty? && !users.include?(user)
        return false
      end
      # Check if groups are defined for the reservation and that the use belongs to one of them
      if !groups.empty? && (user_groups & groups).empty?
        return false
      end
      # Same check for accounts (groups = accounts?)
      if !accounts.empty? && (user_groups & accounts).empty?
        return false
      end
      return true
    end
  end

  class << self
    def run_command(*args)
      stdout_str, status = Open3.capture2(*args)
      return "" unless status.exitstatus == 0
      stdout_str
    rescue Exception => e
      return ""
    end

    def query_slurm
      run_command("scontrol", "show", "--oneliner", "reservation")
    end

    # Parses the output from scontrol show reservation
    # Returns a list of Reservation
    def parse_reservations(slurm_output)
      if slurm_output == "No reservations in the system"
        return []
      end
      reservations = parse_scontrol_show(slurm_output)
      reservations.map { |res| parse_reservation(res) }
    end

    # Parses a single line of scontrol show (in the format of a hash) and returns a Reservation struct from that, with array values parsed
    def parse_reservation(res)
      nodes = parse_scontrol_arr(res[:Nodes])
      users = parse_scontrol_arr(res[:Users])
      flags = parse_scontrol_arr(res[:Flags])
      groups = parse_scontrol_arr(res[:Groups])
      accounts = parse_scontrol_arr(res[:Accounts])
      Reservation.new(res[:ReservationName], nodes, res[:PartitionName], users, groups, flags, accounts, res[:State])
    end

    # Parses comma separated values from scontrol show into an array, empty if "(null)"
    def parse_scontrol_arr(attribute)
      if attribute == "(null)"
        return []
      end
      return attribute.split(",")
    end

    # Parses the output that is in the format returned by scontrol show (key=value key2=value2\n...)
    # Returns a list of hashes
    # Example [{key: value, key2: value2}]
    def parse_scontrol_show(slurm_output)
      lines = slurm_output.strip.split("\n")
      lines.map do |line|
        attributes = line.split(" ")
        attributes.map do |attr|
          key, value = attr.split("=", 2)
          [key.to_sym, value]
        end.to_h
      end
    end

    # Parses scontrol output and filters reservations that can be used
    # Example: [#<struct SlurmReservation::Reservation name="test", nodes=["r07c[01-06]"], partition_name="test", users=["robinkar"], groups=[], flags=["MAINT", "SPEC_NODES", "PART_NODES"], accounts=[], state="ACTIVE">]
    def available_reservations(slurm_output, user)
      reservations = parse_reservations(slurm_output)
      groups = user_groups(user)
      reservations.filter { |res| res.can_use(user, groups) }
    end

    # Fetches the reservations from slurm, parses them and filters them
    # Example: [#<struct SlurmReservation::Reservation name="test", nodes=["r07c[01-06]"], partition_name="test", users=["robinkar"], groups=[], flags=["MAINT", "SPEC_NODES", "PART_NODES"], accounts=[], state="ACTIVE">]
    def reservations(user=ENV["USER"])
      @reservations_cache ||= {}
      @reservations_cache[user] ||= available_reservations(query_slurm, user)
    end

    # List of groups the user belongs to
    # Example: ["robinkar", "ood_installation", "project_1235678"]
    def user_groups(user)
      stdout_str, _, status = Open3.capture3("id", "-Gn", user)
      return [] unless status.exitstatus == 0
      stdout_str.split(" ")
    end
  end
end
