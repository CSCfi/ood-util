"use strict";
var slurm_limits = {};
var slurm_assoc_limits = {};
var slurm_submits = {};
var partition_override = "";

// Regex for dd-hh:mm:ss
// Currently allows values with e.g. seconds > 60
const TIME_REGEX = /^(?:(?:(?:(\d+)-)?(\d+):)?(\d+):)?(\d+)$/;

// Prefix for all form elements used by OOD
const BC_PREFIX = "batch_connect_session_context";

$(document).ready(function () {
  // Populate slurm_limits object with the limits
  const limits_input = $(`#${BC_PREFIX}_csc_slurm_limits`);
  slurm_limits = limits_input.data("limits");
  slurm_assoc_limits = limits_input.data("assoc-limits");
  slurm_submits = limits_input.data("submits");
  partition_override = limits_input.data("partition");
  setup_form();

  save_original_limits();

  // Register event handlers
  register_event_handlers();
  update_min_max(false);
  // Validating immediately makes the message disappear when the page is fully loaded
  // Validate after a short delay
  setTimeout(validate_form, 500);
});

// Disable launch button disabling and validation of form
function setup_form() {
  const form = get_form();
  form.attr("novalidate", "")
  form.find(':submit').removeAttr('data-disable-with');
  form.submit(handle_submit);
}

// Store original min and max from form.yml to use when slurm limit is not defined
function save_original_limits() {
  const elements = get_inputs();
  elements.each((i, el) => {
    $(el).data("orig-min", $(el).attr("min"));
    $(el).data("orig-max", $(el).attr("max"));
  });
}

// Validate inputs and check submits on form changes
function register_event_handlers() {
  const part_input = get_partition_input();
  part_input.change(part_proj_change);
  const project_input = get_project_input();
  project_input.change(part_proj_change);

  const elements = get_inputs();
  elements.each((i, el) => {
    $(el).on("input propertychange", (ev) => validate_input($(ev.currentTarget)));
  });
}

function part_proj_change() {
  update_min_max();
}

function get_form() {
  return $(`#new_${BC_PREFIX}`);
}

// Get all number and text inputs
function get_inputs() {
  return get_form().find("input[type=number],input[type=text]");
}

function get_partition_input() {
  return $(`#${BC_PREFIX}_csc_slurm_partition`);
}

function get_project_input() {
  return $(`#${BC_PREFIX}_csc_slurm_project`);
}

// Get the limits for the currently selected partition
function get_current_limits() {
  const part = get_partition();
  return slurm_limits[part] || {};
}

// Gets the currently selected node type as a string
function get_partition() {
  if (partition_override) {
    return partition_override;
  }
  const part_input = get_partition_input();
  const part = part_input.val();
  return part;
}

// Ask user to submit if form has invalid data, otherwise just submit
function handle_submit(ev) {
  ev.preventDefault()

  validate_form();
  const valid = !ev.currentTarget.checkValidity || ev.currentTarget.checkValidity();
  if (valid) {
    submit_form();
  } else {
    show_confirm_modal("Form invalid", "The form contains invalid parameters. Are you sure you want to launch the application?", submit_form, "Launch");
    get_form()[0].reportValidity();
  }
}

// Actually submit the form bypassing the jQuery handler
function submit_form() {
  const form = get_form();
  form.find(':submit').prop('disabled', true);
  form[0].submit();
}

function update_min_max(validate = true) {
  const inputs = get_inputs();
  inputs.each((i, inp) => update_input($(inp)));
  if (validate) {
    validate_form();
  }
}

// Update the min and max attributes of an input elements
function update_input(el) {
  // Use data-min and data-max to determine which slurm limit value to use
  const min = el.data("min");
  const max = el.data("max");
  if (min != null) {
    const limit = get_current_limits()[min];
    const actual_limit = limit == null ? el.data("orig-min") : limit;
    if (limit == null) {
      el.removeAttr("min");
    } else {
      el.attr("min", actual_limit);
    }
  }
  if (max != null) {
    const limit = get_current_limits()[max];
    const actual_limit = limit == null ? el.data("orig-max") : limit;
    if (limit == null) {
      el.removeAttr("max");
    } else {
      el.attr("max", actual_limit);
    }
  }
}

// Set the custom validity on a jQuery element, returns false if element didn't exist
function setValidity(jqEl, msg) {
  if (jqEl[0] == null) {
    return false;
  }
  jqEl[0].setCustomValidity(msg);
  return true;
}

// Check amount of submits by project and partition in the queue
function check_submits() {
  if (slurm_submits == null || slurm_assoc_limits == null) {
    return;
  }
  const part_input = get_partition_input();
  const proj_input = get_project_input();
  const partition = part_input.val() || partition_override;
  const project = proj_input.val();
  const proj_part = `${project}_${partition}`;
  const submits = slurm_submits[proj_part] || 0;
  const assoc_limits = slurm_assoc_limits[proj_part];
  if (assoc_limits == null || assoc_limits["maxsubmit"] == null)
    return;
  const maxsubmit = assoc_limits["maxsubmit"];

  setValidity(proj_input, "");
  setValidity(part_input, "");
  if (maxsubmit === 0) {
    setValidity(proj_input, "Project has no BU left");
  } else if (submits >= maxsubmit) {
    const msg = `${project} already has ${submits} job${submits > 1 ? "s" : ""} out of maximum ${maxsubmit} in the ${partition} queue`;
    // Attach message to project dropdown if partition dropdown is missing
    if (!setValidity(part_input, msg)) {
      setValidity(proj_input, msg);
    }
  } 

  if (proj_input[0] != null) {
    proj_input[0].reportValidity();
  }
  if (part_input[0] != null) {
    part_input[0].reportValidity();
  }
  return false;
}

// Check validity of all inputs in the form
function validate_form() {
  check_submits();
  const elements = get_inputs();
  elements.each((i, el) => {
    validate_input($(el));
  });
}

// Check the validity of an input element
function validate_input(el) {
  if (!(el.attr("type") === "number" || el.attr("type") === "text")) {
    return;
  }

  // Values as strings, keep as is for formatting output
  const min = el.attr("min");
  const max = el.attr("max");
  const val = el.val();

  // Convert number fields to int, time to int (seconds), use strings for the rest
  const parse_function = el.attr("type") === "number" ?
    parseInt :
    el.data("type") === `time` ?
    parse_time : v => v;

  const n_min = parse_function(min);
  const n_max = parse_function(max);
  const n_val = parse_function(val);

  if (min != null && n_val < n_min) {
    setValidity(el, `Value is less than the minimum for partition (${min})`);
  } else if (max != null && n_val > n_max) {
    setValidity(el, `Value exceeds the maximum for partition (${max})`);
  } else {
    // Input element value ok (pattern/format is checked automatically)
    setValidity(el, "");
  }
  el[0].reportValidity();
  return false;
}

// Return the time as seconds
function parse_time(time_str) {
  if (time_str == null) {
    return 0;
  }
  const match = time_str.match(TIME_REGEX);
  if (match == null)
    return 0;

  // Drop full match, convert match groups to ints
  const [d, h, m, s] = match.slice(1).map((e) => parseInt(e) || 0);

  // Time as seconds
  return d * 24 * 60 * 60 + h * 60 * 60 + m * 60 + s;
}

// Show the Bootstrap modal for confirming submit
function show_confirm_modal(title, text, callback, confirmText = "OK", cancelText = "close") {
  // HTML for the modal dialog
  const modal_html = `
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title">${title}</h5>
        <button type="button" class="close" data-dismiss="modal" aria-label="Close">
          <span aria-hidden="true">&times;</span>
        </button>
      </div>
      <div class="modal-body">
        <p>${text}</p>
      </div>
      <div class="modal-footer">
        <button type="button" id="confirmButton" class="btn btn-primary">${confirmText}</button>
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
      </div>
    </div>
  </div>`

  let modal = $('#confirmModal');
  if (!modal.length) {
    $('body').append('<div class="modal" tabindex="-1" role="dialog" id="confirmModal"></div>');
    modal = $('#confirmModal');
  }
  modal.html(modal_html);
  modal.find('#confirmButton').on("click", callback);
  modal.modal("show");
}
