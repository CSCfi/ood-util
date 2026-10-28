# Checks the availability of partitions from Slurm based on partition and node state.
'''
Example output:

SlurmPartitionState.states
{
  "small": {
    "name": "small", "avail": "up", "usable": 0, "total": 8,
    "states": {"drain$": 3, "maint": 5}, "available": false
  },
  "large": {
    "name": "large", "avail": "up", "usable": 100, "total": 102,
    "states": {"allocated": 90, "mixed": 10, "down*": 2}, "available": true
  }
}
'''
require 'open3'

module SlurmPartitionState

  # Base node states (without suffix flags) where jobs can't run.
  # Everything else is usable, e.g. idle, mixed, allocated, completing, planned, blocked, cloud, power saving
  # and reboot states, and nodes in a (non-maintenance) reservation (resv/reserved).
  # Maintenance reservations show up as maint or with the $ suffix.
  # Unrecognized states are counted as usable so that unexpected output doesn't cause false warnings.
  UNUSABLE_STATES = [
    "down",
    "drain", "drained", "draining", "drng",
    "fail", "failing",
    "future", "futr",
    "maint",
    "unk", "unknown",
    "inval",
    "no_respond",
  ].freeze

  # Suffixes that make the node unusable:
  # $ = in a maintenance reservation, * = not responding.
  # Other suffixes (e.g. ~ powered off, # powering up, @ pending reboot) are temporary and don't prevent jobs.
  UNUSABLE_SUFFIXES = ["$", "*"].freeze

  # How long the partition states are cached for (seconds).
  CACHE_EXPIRY = 300

  class << self
    # Runs the specified command
    # Commandline arguments separated into parameters (normal Open3.capture2 usage)
    def run_command(*args)
      stdout_str, status = Open3.capture2(*args)
      return "" unless status.exitstatus == 0
      stdout_str
    rescue
      return ""
    end

    # Cached partition states, e.g. {"small" => {name: "small", avail: "up", ..., available: false}}
    def states
      Rails.cache.fetch("csc_slurm_partition_states", expires_in: CACHE_EXPIRY) do
        parse_states(query_states)
      end
    end

    def query_states
      # One line per partition and node state, e.g.
      # small|up|drain$|3
      # small|up|maint|5
      run_command("sinfo", "--noheader", "--Format", "PartitionName:|,Available:|,StateLong:|,Nodes:")
    end

    # Whether a node state (StateLong, e.g. "idle", "mixed-", "drain$", "down*") allows running jobs
    def usable_state?(state)
      return false if UNUSABLE_SUFFIXES.any? { |suffix| state.include?(suffix) }
      base = state[/\A[a-z_]+/]
      !UNUSABLE_STATES.include?(base)
    end

    def parse_states(slurm_output)
      slurm_output.strip.split("\n")
        .map { |line| line.split("|", 4).map { |v| v.to_s.strip } }
        # Skip malformed lines so that unexpected output doesn't cause false warnings
        .select { |name, _, state, nodes| !name.empty? && !state.to_s.empty? && nodes.to_s.match?(/\A\d+\z/) }
        .group_by(&:first)
        .transform_values { |lines| partition_state(lines) }
    end

    # Combines the sinfo lines (one per node state) of a partition into a single Hash
    def partition_state(lines)
      name, avail = lines.first
      states = lines
        .map { |_, _, state, nodes| [state.downcase, nodes.to_i] }
        .group_by(&:first)
        .transform_values { |counts| counts.sum(&:last) }
      usable = states.select { |state, _| usable_state?(state) }.values.sum
      {
        name: name,
        avail: avail.to_s.downcase,
        usable: usable,
        total: states.values.sum,
        states: states,
        # Partition accepts and starts jobs and has at least one node that can run them
        available: avail.to_s.downcase == "up" && usable > 0,
      }
    end
  end
end
