# Form validation

The form validation is done by getting the Slurm limits when the app form is rendered. Limits are then passed in a hidden field in the form.
The hidden field contents is then parsed as JSON and then used to validate the form using the HTML5 custom validation features.
Form validation is intended to be as generic as possible and work on any the systems (Puhti, Mahti, LUMI) without needing to implement separate logic for each of them.
The biggest differences between the systems are regarding SMT, MaxMemPerCPU and TRES availability (NVME+GPU).

## Expected behaviour

### Slurm resource limits

#### Node limits
Some partitions have different types of nodes with different limits.
For example, the *small* partition on Puhti can use *M*, *L* or *IO* nodes.
Slurm automatically selects the correct node type based on resources requested, so we want to always select the largest value allowed for resources.
For the *small* partition, the maximum NVME size for each node type is 0GB, 1490GB and 3600GB, so the maximum possible is 3600GB.

#### QoS limits

Some partitions have QoS limits defined.
In these cases we want to take the lower of the limits.
For example, the nodes for interactive partition has 40 cores, but the interactive QoS is set at `cpu=8,gres/nvme=720,mem=76G` (maxtrespu), so maximum should be 8 for the interactive partition.

##### maxtres vs maxtrespu vs maxtrespa

For *maxtrespu* (per user) we count the currently running resources (jobs with state *R*) for the user for that partition.
If the *maxtrespu* with the user's used resources subtracted is lower than the node limit, we use this limit instead.

*maxtres* and *maxtrespa* (per account (project)) are not in practice used/relevant for the form validation, but are still supported by the form validation.
We treat *maxtrespa* in the same way as *maxtrespu* (I'm unsure if we should include other users' used resources in *maxtrespa*).

#### MaxMemPerCPU

LUMI and Mahti have MaxMemPerCPU set for some partitions.
The value is parsed and included in the data passed to the form, with dynamically updating help text letting the user know that the amount of memory depends on the amount of CPUs they choose.
The actual submission logic for MaxMemPerCPU needs to be handled in `submit.yml.erb`.

### Limits defined in the form

`form.yml.erb` allows settings minimum and maximum values for the form in a few different ways.
The standard OOD way is to set `max` or `min` for the form attribute.
In addition to that, we also allow setting min/max values for specific partitions, by setting e.g. `min-interactive` on the form attribute, and in the `csc_slurm_limits` form attribute by directly overriding the Slurm limits found (see [Smart attributes README](https://gitlab.ci.csc.fi/compen/open-ondemand/ood-util/-/blob/master/attributes/README.md#setup).
When the form is changed, we always check which limit is in effect (lowest).

**Short example:**  
The user has no jobs running.
The interactive partition has node limit of 40 cores, and *maxtrespu* limit of `cpu=8`.
In `form.yml.erb` `csc_cores` has the `max` attribute set to 6 and the `max-test` attribute set to 1.  
When the user goes to the app form, selects the *interactive* partition and chooses 8 cores.
The user now sees the error message `Value exceeds the maximum allowed (6)` since the `max` for this particular app was set to 6.  
The user then changes the cores to 5 (which hides the error), launches the app and opens the form again.
Since the user now has 5 cores used, they now see the error `Value exceeds the maximum for partition (5 used out of maximum 8 per user)`, since the *maxtrespu* QoS limit is now the lowest limit.
If the user changes to the test partition, they now see the error message `Value exceeds the maximum allowed (1)` instead, since the limit set in `form.yml.erb` for the test partition is now used.


## Backend
The backend is the part that runs on the OOD node when the app form is rendered.
The main parts are `ood-util/attributes/csc_slurm_limits.rb` and `ood-util/scripts/slurm_limits.rb`.
Currently the limits that are fetched from Slurm are the resource limits for the nodes for time, CPU cores, memory, NVME and number of GPUs.
Amount of submits is also validated, the maximum number of submissions for each project and partition is fetched together with the amount of running jobs that the user has.
Limits are cached for the whole PUN session.

### slurm_limits.rb
The `slurm_limits.rb` file is a Ruby module that fetches the limits and other info from Slurm.
SlurmLimits uses [Open3](https://docs.ruby-lang.org/en/2.7.0/Open3.html) for running Slurm commands and then parses the result into Structs.

The following commands are used by SlurmLimits for getting the limits from Slurm:
```
# Commands for resource limits

# sinfo gives most of the relevant limits, some partitions can use different node types, eg IO or M
# the maximum value for each resource is used if multiple node types are possible
sinfo --noheader --Format "PartitionName:|,Time:|,Memory:|,SocketCoreThread:|,Gres:"

# sacctmgr show qos gives the qos limits, in this case only the interactive partition limits are relevant
sacctmgr --noheader --parsable2 show qos format=Name,MaxTres,MaxTresPA,MaxTresPU

# get the name of the qos used for each partition
scontrol show partition --oneliner
```
```
# Maximum number of submits and current job submission amount

# sacctmgr show assoc gives the max submits for each partition and project
# only MaxSubmits is used currently to allow the user to queue up jobs even if they won't run immediately
sacctmgr --noheader --parsable2 show assoc format=Partition,Account,MaxJobs,MaxSubmit where user=$USER

# get the amount of submissions the user has for each partition and project
squeue --noheader --Format "JobID:|,Account:|,Partition:|,StateCompact:|,MinCpus:|,tres-alloc:|" --user $USER
```
```
# Partition availability (slurm_partition_state.rb)

# partition state (up/down/drain/inact), node state and node count, one line per partition and node state
sinfo --noheader --Format "PartitionName:|,Available:|,StateLong:|,Nodes:"
```

#### Resource limits
The resource limits are retrieved from SlurmLimits as `limits = SlurmLimits.limits`.
Limits are returned in the following format:
```
{
  "small": {
    "name": "small",
    "time": "3-00:00:00",
    "mem": 373,
    "cpu": 40,
    "qos": {},
    "gres/nvme": 3600,
    "max_mem_per_cpu": 0,
    "gpu_types": null,
    "threads_per_core": 2
  },
  "interactive": {
    "name": "interactive",
    "time": "7-00:00:00",
    "mem": 373,
    "cpu": 40,
    "qos": {
      "name": "interactive",
      "maxtres": {},
      "maxtrespa": {},
      "maxtrespu": {
        "cpu": 8,
        "gres/nvme": 720,
        "mem": 76.0
      }
    },
    "max_mem_per_cpu": 1.8310546875,
    "gpu_types": null,
    "threads_per_core": 2,
    "gres/nvme": 3600
  },
  "gputest": {
    "name": "gputest",
    "time": "15:00",
    "mem": 478,
    "cpu": 128,
    "qos": {
    },
    "max_mem_per_cpu": 0,
    "gpu_types": [
      "a100"
    ],
    "threads_per_core": 2,
    "gres/gpu:a100": 4,
    "gres/nvme": 3500
  }
}
```

The `limits` function uses the `sinfo ...` and `sacctmgr ... show qos ...` commands mentioned earlier.
Memory limits are converted to GiB from MB.
CPU limit is calculated using sockets * cores * threads from `sinfo`
For the qos limits the lower value for each field is always used, overrides the limit from `sinfo` if lower.
Node types are combined, no difference is made between eg. M and IO node for small partition, the higher limit is used for each resource.

#### Submission limits
The submissions limits and submission amount are retrieved from SlurmLimits as
```
# Limits
assoc_limits = SlurmLimits.assoc_limits
# Current submissions
submits = SlurmLimits.submits
```
Example output, assoc_limits:
```
{
    "project_2001659_interactive": {
        "maxjobs": 1,
        "maxsubmit": 1
    },
    "project_2001659_small": {
        "maxjobs": 200,
        "maxsubmit": 400
    },
    "project_2001659_test": {
        "maxjobs": 1,
        "maxsubmit": 2
    },
    ...
}
```
Example output, submits:
```
{
    "project_2001659_interactive": 1,
    "project_2001659_test": 1
}
```

### Partition availability (`slurm_partition_state.rb`)
`SlurmPartitionState.states` returns the availability of each partition, used for warning the user if the selected partition is unlikely to run jobs.
Partition and node states are queried using sinfo and cached for 5 minutes.

A partition is considered unavailable (`available: false`) if the partition is not `up` (e.g. `down`, `drain` or `inact`), or if none of its nodes are usable.

A node is usable if it can run jobs now, once its current jobs finish, or once Slurm has powered it up or rebooted it:
- Ready or running jobs: `idle`, `mixed`, `allocated`, `completing`, `planned`, `blocked`
- Power saving: `cloud`, `power_down`, `powering_down`, `powered_down`, `powering_up`
- Rebooting: `boot`, `reboot_issued`, `reboot_requested`
- In a non-maintenance reservation: `resv`/`reserved`

A node is not usable if it has one of the following states:
- Down or failing: `down`, `fail`/`failing`, `inval`, `unknown`
- Drained by admins: `drain`/`drained`/`draining`
- Not yet in service: `future`
- Maintenance: `maint`

or one of the following suffixes, regardless of the state:
- `$`: in a maintenance reservation
- `*`: not responding

```
{
  "small": {"name": "small", "avail": "up", "usable": 0, "total": 8, "states": {"drain$": 3, "maint": 5}, "available": false},
  "large": {"name": "large", "avail": "up", "usable": 100, "total": 102, "states": {"allocated": 90, "mixed": 10, "down*": 2}, "available": true}
}
```

### csc_slurm_limits.rb
`csc_slurm_limits.rb` is a smart attribute for OOD.
It is used to generate a hidden input field with JSON data and is used for passing the data from the backend to the frontend.
See [Smart attributes README](https://gitlab.ci.csc.fi/compen/hpc-environment/ood-util/-/blob/master/attributes/README.md) for usage instructions.
The attributes `nofetchlimits`, `nosubmitscount` can be used for disabling fetching of limits from SlurmLimits, and `nopartitionstate` for disabling fetching of partition states from SlurmPartitionState.
On the `data` attribute `limits`, `assoc_limits`, `submits` and `partition_states` can be set to override the values from Slurm.
If fixed partition is used for the form the `partition` attribute can be set on `csc_slurm_limits` `data` attribute.

## Frontend
The frontend parses parses `limits`, `assoc_limits` and `submits` data fields on the `csc_slurm_limits` form field as JSON and uses that data to update the minimum and maximum values on the form.
The validation utilizes the [HTML5 validation features](https://developer.mozilla.org/en-US/docs/Learn/Forms/Form_validation) to validate the form and show error messages.
As the limits might be incorrect, form submission when the form is invalid is not prevented as it usually is in OOD, instead a confirm dialog is shown asking the user to confirm submitting a possibly invalid form.

Partition and project are read from the form fields for `csc_slurm_project` and `csc_slurm_partition`.
If a partition override was provided by setting the `partition` attribute in the `data` attribute on `csc_slurm_limits` that value is used instead of `csc_slurm_partition`.

### Limits
All number and text inputs in the form are validated.
The type is detected automatically based on the field type.
Validation of time in the format `1-00:00:00` can be done by setting `type: time` in the `data` attribute on the field.
When the project or partition in the form are changed all form fields are updated with limits for that partition by setting `max` and `min` on the form elements.
When any of the input elements in the form are changed all form elements will be validated.
If an element has an invalid value, which is lower or higher than the limit or invalid format, an error will be shown by setting a custom error message.
Which value is used from the Slurm limits object can be set by setting `data-max` and `data-min` on the form fields. That can be done by setting `min` and `max` in the `data` attribute on the form field.

### Partition availability
If the selected partition is unavailable, a warning is shown as red text in the help text of the partition dropdown (or the project dropdown if the partition is fixed) stating that the partition may not be available.
This is only a warning and does not make the form invalid, as jobs can still be queued and will start once the partition becomes available.
No warning is shown when a reservation is selected, as the reservation's nodes may be available even if the rest of the partition is not.

### Submission limits
The max submission limit is handled by checking the submission limits every time the project or partition changes.
If above the max submission limit or the project has max submissions set to 0 an error message is shown on the project and partition fields.
