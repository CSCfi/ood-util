# Form validation

The form validation is done by getting the Slurm limits when the app form is rendered, pass the limits in a hidden field in the form.
The hidden field contents is then parsed as JSON and then used to validate the form using the HTML5 custom validation features.

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
sinfo --noheader --format %R|%l|%m|%z|%G

# sacctmgr show qos gives the qos limits, in this case only the interactive partition limits are relevant
sacctmgr --noheader -p show qos format=Name,MaxTres%100,MaxTresPA%200
```
```
# Maximum number of submits and current job submission amount

# sacctmgr show assoc gives the max submits for each partition and project
# only MaxSubmits is used currently to allow the user to queue up jobs even if they won't run immediately
sacctmgr --noheader -p show assoc format=Partition,Account,MaxJobs,MaxSubmit where user=$USER

# get the amount of submissions the user has for each partition and project
squeue --noheader --format "%i|%a|%P|%t" --user $USER
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
        "gres/nvme": 3600,
        "gres/gpu:v100": 0
    },
    ...
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

### csc_slurm_limits.rb
`csc_slurm_limits.rb` is a smart attribute for OOD.
It is used to generate a hidden input field with JSON data and is used for passing the data from the backend to the frontend.
See [Smart ttributes README](https://gitlab.ci.csc.fi/compen/hpc-environment/ood-util/-/blob/master/attributes/README.md) for usage instructions.
The attributes `nofetchlimits`, `nosubmitscount` can be used for disabling fetching of limits from SlurmLimits.
On the `data` attribute `limits`, `assoc_limits` and `submits` can be set to override the limits from SlurmLimits.
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

### Submission limits
The max submission limit is handled by checking the submission limits every time the project or partition changes.
If above the max submission limit or the project has max submissions set to 0 an error message is shown on the project and partition fields.
