require "open3"

module SlurmReservation

  Reservation = Struct.new(:name, :nodes, :partition_name, :users, :groups, :flags, :accounts, :state, :start_time, :end_time) do
    attr_reader :maintenance

    def can_use(user, user_groups)
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

    def partitions
      @partitions ||= self.partition_name != "(null)" ? [self.partition_name] : SlurmReservation.node_partitions(self.nodes)
    end

    # List of nodes in maintenance by this reservation.
    def maintenance_nodes
      return [] if self.state != "ACTIVE" || !self.flags.include?("MAINT")
      return self.expanded_nodes
    end

    # Set the maintenance status on the reservation.
    # Checks if the reservation is a node-specific reservation and checks if all of those nodes have maintenance reservations.
    def set_maintenance(maint_nodes)
      @maintenance = self.expanded_nodes.all? { |node| maint_nodes.include?(node) }
    end

    # Expanded list of nodes in reservation, i.e. ["c1200", "c1201"] instead of "c[1200-c1201]"
    def expanded_nodes
      @expanded_nodes ||= SlurmReservation.expand_nodes(self.nodes)
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

    # Gets the list of partitions for a set of nodes
    def node_partitions(node_str)
      output = run_command("scontrol", "show", "--oneliner", "node", node_str)
      nodes = parse_scontrol_show(output)
      nodes.map { |node|
        parse_scontrol_arr(node[:Partitions])
      }.flatten.uniq
    rescue => e
      Rails.logger.error("Error getting partitions for nodes #{node_str}: #{e}")
      []
    end

    def expand_nodes(node_str)
      output = run_command("scontrol", "show", "hostname", node_str)
      output.lines.map(&:strip)
    rescue => e
      Rails.logger.error("Error expanding list of nodes (#{node_str}): #{e}")
      []
    end

    # Parses the output from scontrol show reservation
    # Returns a list of Reservation
    def parse_reservations(slurm_output)
      if slurm_output.include?("No reservations in the system")
        return []
      end
      reservations = parse_scontrol_show(slurm_output)
      reservations.map { |res| parse_reservation(res) }
    end

    # Parses a single line of scontrol show (in the format of a hash) and returns a Reservation struct from that, with array values parsed
    def parse_reservation(res)
      users = parse_scontrol_arr(res[:Users])
      flags = parse_scontrol_arr(res[:Flags])
      groups = parse_scontrol_arr(res[:Groups])
      accounts = parse_scontrol_arr(res[:Accounts])
      start_time = Time.parse(res[:StartTime])
      end_time = Time.parse(res[:EndTime])
      Reservation.new(res[:ReservationName], res[:Nodes], res[:PartitionName], users, groups, flags, accounts, res[:State], start_time, end_time)
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
      maintenance_nodes = reservations.map(&:maintenance_nodes).flatten.uniq
      reservations
        .filter { |res| res.can_use(user, groups) }
        .tap { |avail_res| avail_res.each { |res| res.set_maintenance(maintenance_nodes) } }
    end

    # Fetches the reservations from slurm, parses them and filters them
    # Example: [#<struct SlurmReservation::Reservation name="test", nodes=["r07c[01-06]"], partition_name="test", users=["robinkar"], groups=[], flags=["MAINT", "SPEC_NODES", "PART_NODES"], accounts=[], state="ACTIVE">]
    def reservations(user = ENV["USER"])
      cache_expiry = nil
      result = Rails.cache.fetch("slurm_reservations_#{user}", expires_in: 10.minutes) do
        avail_reservations = available_reservations(query_slurm, user)
        avail_reservations.each { |res|
          if res.start_time > Time.now && (cache_expiry.nil? || res.start_time < cache_expiry)
            cache_expiry = res.start_time
          end
          if res.end_time > Time.now && (cache_expiry.nil? || res.end_time < cache_expiry)
            cache_expiry = res.end_time
          end
        }
      end
      # Update expiry time of cache to be after the next start or end of a reservation
      if cache_expiry != nil
        Rails.cache.write("slurm_reservations_#{user}", result, expires_in: [cache_expiry - Time.now + 1.second, 10.minutes].min)
      end
      result
    end

    # Used in submit.yml.erb files to determine which partition to really use.
    def partition_to_use(reservation, partition)
      # User selected reservation => use partition from reservation.
      # User selected partition or reservation has no partition => use user selected partition.
      res = reservations.find { |r| r.name == reservation }
      res.nil? || res.partition_name == "(null)" ? partition : res.partition_name
    end

    # Output the maximum run time possible for the reservation for sbatch --time parameter.
    # Fallback to user defined time if no reservation or any parsing fails.
    def max_time(reservation, user_defined_time)
      return user_defined_time if reservation.blank?

      margin = 5.minutes
      res = reservations.find { |r| r.name == reservation }
      end_time = res&.end_time
      # Use user defined time if job is started within last 20 minutes of queueing.
      return user_defined_time if end_time.nil? || Time.now > end_time - margin

      # Parse e.g. 1-23:34:45 (%d-%H:%M:%S)
      re = /^(?:(?:(?:(\d+)-)?(\d+):)?(\d+):)?(\d+)$/
      m = re.match(user_defined_time)
      requested_seconds = m[1].to_i.days + m[2].to_i.hours + m[3].to_i.minutes + m[4].to_i
      return user_defined_time if Time.now + requested_seconds < end_time

      # 20 minute margin to allow time for queueing.
      max_seconds = (end_time - margin - Time.now).to_i
      days = (max_seconds/86400).to_i
      formatted_time = Time.at(max_seconds).utc.strftime("#{days}-%H:%M:%S")
      return formatted_time
    rescue => e
      Rails.logger.error("Error getting max time for job: #{e}")
      user_defined_time
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
