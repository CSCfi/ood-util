# Smart attributes

Smart attributes are form elements used in OOD interactive app forms. After loading they can be used in the same way as normal attributes defined in the form template and even modified by defining them again in the attributes section of `form.yml.erb`.  
Ruby code in `form.yml.erb` is executed every time the app template is rendered, which due to a bug in OOD happens several times per dashboard page load. The code in the smart attributes only runs when the actual interactive app form is loaded. This allows for much more complex scripts without the performance impact. The smart attributes must be loaded before use.  
  
Example `form.yml.erb` that uses some smart attributes:
```yml
# form.yml.erb
<% require "/appl/opt/ood_util/attributes/csc_slurm_partition" -%>
<% require "/appl/opt/ood_util/attributes/csc_slurm_project" -%>
<% require "/appl/opt/ood_util/attributes/csc_cores" -%>

cluster: "puhti"

form:
  - csc_slurm_project
  - csc_slurm_partition
  - csc_cores
```
The above form allows the user to select project and partitions from a list that is fetched from Slurm and allows the user to select the amount of CPU cores for the job.

### csc_slurm_partition/project
Use these to get the available projects and partitions that the user can submit a job for. These are automatically submitted to Slurm.  
A partition that can't be changed by the user but submitted is to Slurm can be defined as
```yml
# form.yml.erb
<% require "/appl/opt/ood_util/attributes/csc_slurm_partition" -%>
attributes:
  csc_slurm_partition:
    value: "interactive"
    fixed: true
form:
  - csc_slurm_partition
```

### csc_cores/memory/nvme/time/gpu
Various elements for letting the user select CPUs, memory, NVME size, time and GPUs for the job. These values are not automatically submitted to Slurm so `submit.yml.erb` must be modified.  
Example:
```yml
# submit.yml.erb
batch_connect:
  template: "basic"

script:
  native:
    - '-c'
    - '<%= csc_cores %>'
    - '-t'
    - '<%= csc_time %>'
    - '--mem=<%= csc_memory %>G'
    - '--gres=nvme:<%= csc_nvme.blank? ? 0 : csc_nvme %>,gpu:v100:<%= csc_gpu.blank? ? 0 : csc_gpu %>'
```


### csc_slurm_limits
A hidden input element that contains the limits for CPUs, memory, NVME, time and GPU. See form validation section.

### csc_extra_desc
A form element for writing a longer description using Markdown and HTML for the interactive app and form.  
```yml
# form.yml.erb
<% require "/appl/opt/ood_util/attributes/csc_extra_desc" -%>
attributes:
  csc_extra_desc:
    desc: |
      Insert the description here, or maybe a [link](https://docs.csc.fi)
      Images also work ![ood](https://openondemand.org/assets/images/ood_logo_stack_rgb.svg)
form:
  - csc_extra_desc
```

## Interactive app form validation
The errors that Slurm gives when an user tries to submit a job with for example higher time limit than the partition allows can be quite confusing. To improve the user experience the form can be validated clientside before sending it. Note that the clientside form validation does not prevent the user from submitting the form with values outside the allowed values. If that needs to be prevented it must be done for example in `submit.yml.erb`

### Setup
`ood_util/forms/form_validated.js` must be linked or copied to the app root folder as `form.js`. This can be done with the command `ln -s /appl/opt/ood_util/forms/form_validated.js form.js`.  
`csc_slurm_project`, `csc_slurm_partition`, `csc_slurm_limits` must be `require`d and included in the form section of `form.yml.erb`.

Basic usage:
```yml
# form.yml.erb
<% require "/appl/opt/ood_util/attributes/csc_slurm_project" -%>
<% require "/appl/opt/ood_util/attributes/csc_slurm_partition" -%>
<% require "/appl/opt/ood_util/attributes/csc_slurm_limits" -%>
<% require "/appl/opt/ood_util/attributes/csc_time" -%>
<% require "/appl/opt/ood_util/attributes/csc_cores" -%>
<% require "/appl/opt/ood_util/attributes/csc_memory" -%>
<% require "/appl/opt/ood_util/attributes/csc_nvme" -%>
<% require "/appl/opt/ood_util/attributes/csc_gpu" -%>

cluster: "puhti"

form:
  - csc_slurm_project
  - csc_slurm_partition
  - csc_time
  - csc_cores
  - csc_memory
  - csc_nvme
  - csc_gpu
  - csc_slurm_limits
```
The above form will create a form containing inputs for project, partition, time, CPUs, memory, NVME, GPUs that are automatically validated using limits from Slurm.  

Advanced usage:
```yml
# form.yml.erb
<% require "/appl/opt/ood_util/attributes/csc_slurm_project" -%>
<% require "/appl/opt/ood_util/attributes/csc_slurm_partition" -%>
<% require "/appl/opt/ood_util/attributes/csc_slurm_limits" -%>
<% require "/appl/opt/ood_util/attributes/csc_time" -%>
<% require "/appl/opt/ood_util/attributes/csc_cores" -%>
<% require "/appl/opt/ood_util/attributes/csc_memory" -%>
<% require "/appl/opt/ood_util/attributes/csc_nvme" -%>
<% require "/appl/opt/ood_util/attributes/csc_gpu" -%>

cluster: "puhti"

attributes:
  csc_cores:
    value: 1 # Default/initial value
    max: 4 # Used if a limit for the partition isn't found by csc_slurm_limits
    label: Cores # Custom label for the field
  csc_slurm_limits:

    # Override the limits from csc_slurm_limits
    data:
      # Uncomment the next line if you are using a fixed partition (see csc_slurm_partition usage)
      # partition: "interactive"
      # nofetchlimits: true # Disables fetching the limits from Slurm (uncomment to define all limits ourselves)
      nosubmitscount: true # Disable checking amount of queued jobs
      limits:
        interactive:
          cpu: 2
          my_custom_limit: 100 # Define a custom limit for a field we create
        small: # Define custom limits for small partition
          my_custom_limit: 200
          time: "1-00:00:00" # Override the time limit used to validate csc_time
          cpu: 20 # Override max CPUs, used in csc_cores
          mem: 32 # Override max memory, used in csc_memory
          gres/nvme: 64 # Override max NVME size, used in csc_nvme
          gres/gpu:v100: 1 # Override max GPU amount, used in csc_gpu
  

  # Create a custom number input that we want to be validated
  my_custom_field:
    widget: number_field
    data:
      min: "cpu" # We want our input value to be greater than or equal to the number of CPU cores
      max: "my_custom_limit" # Our field will have a max value defined by my_custom_limit per partition
    max: 10 # Our field will have a max value of 10 for all partitions except small and interactive (which have limits defined above)

form:
  - csc_slurm_project
  - csc_slurm_partition
  - csc_time
  - csc_cores
  - csc_memory
  - csc_nvme
  - csc_gpu
  - my_custom_field
  - csc_slurm_limits
```
