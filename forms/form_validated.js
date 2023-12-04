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

// Only setup form once, use DOMContentLoaded as it should fire before the ready event.
// Use the ready event as fallback as it will always fire while DOMContentLoaded will not fire if
// event listener was added after DOM was ready.

(function() {
  let loaded = false;
  function init() {
    if (!loaded) {
      loaded = true;
      setup_form();
      setup_reset_cache_button();
    }
  }
  document.addEventListener("DOMContentLoaded", init);
  $(init);
})();

function setup_form() {
  // Populate slurm_limits object with the limits
  const limits_input = $(`#${BC_PREFIX}_csc_slurm_limits`);
  slurm_limits = limits_input.data("limits") || {};
  slurm_assoc_limits = limits_input.data("assoc-limits") || {};
  const submits = limits_input.data("submits") || [];
  partition_override = limits_input.data("partition") || "";

  const form = get_form();

  if (form.length > 0) {
    $(window).on("load", function () {
      setTimeout(validate_form, 100);
    });
  } else {
    return;
  }

  // Disable launch button disabling and validation of form
  form.attr("novalidate", "")
  form.find(':submit').removeAttr('data-disable-with');
  form.submit(handle_submit);
  save_original_limits();

  slurm_submits = count_running_resources(submits);

  // Register event handlers
  register_event_handlers();
  update_min_max(false);
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
  get_partition_input().change(part_proj_change);
  get_project_input().change(part_proj_change);
  get_reservation_input().change(part_proj_change);

  const elements = get_inputs();
  elements.each((i, el) => {
    $(el).on("input propertychange", (ev) => validate_input($(ev.currentTarget)));
  });
}

function count_running_resources(submits) {
  const jobs = {
    "partition": {},
    "project": {},
    "numjobs": {}
  };
  if (submits == null) {
    return jobs;
  }
  for (const job of submits) {
    for (const [res, value] of Object.entries(job["tres"])) {
      if (job["state"] !== "R") {
        continue;
      }
      jobs["partition"][job["part"]] = jobs["partition"][job["part"]] || {};
      jobs["project"][job["acc"]] = jobs["project"][job["acc"]] || {};

      if (res in jobs["partition"][job["part"]]) {
        jobs["partition"][job["part"]][res] += value;
      } else {
        jobs["partition"][job["part"]][res] = value;
      }

      if (res in jobs["project"][job["acc"]]) {
        jobs["project"][job["acc"]][res] += value;
      } else {
        jobs["project"][job["acc"]][res] = value;
      }
    }
    const key = `${job["acc"]}_${job["part"]}`;
    if (key in jobs["numjobs"]) {
      jobs["numjobs"][key] += 1;
    } else {
      jobs["numjobs"][key] = 1;
    }
  }
  return jobs;
}

function part_proj_change() {
  // Need a short delay to let the normal OOD change handler run first. This is needed when
  // changing to a project that doesn't have access to the currently selected project
  setTimeout(update_min_max, 50);
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

function get_reservation_input() {
  return $(`#${BC_PREFIX}_csc_slurm_reservation`);
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
  const res_input = get_reservation_input();
  const res_part = res_input.find(":selected").data("partition");
  return res_input.is(":visible") && (res_part == null || res_part =="(null)") ? part : res_part;
}

function get_project() {
  const proj_input = get_project_input();
  const proj = proj_input.val();
  return proj;
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
  update_gpu_type();
  if (validate) {
    validate_form();
  }
}

function update_gpu_type() {
  const limits = get_current_limits();
  const gpu_help = $("#partition_gpu_help");
  const gpu_name_help = $("#partition_gpu_name");
  const gpu_type_help = $("#partition_gpu_type");
  if (limits.gpu_types && limits.gpu_types.length > 0) {
    const gpu_name = limits.gpu_types[0].toUpperCase();
    const gpu_type = gpu_name === "MI250" ? "GCD" : "GPU";
    gpu_name_help.text(gpu_name);
    gpu_type_help.text(gpu_type);

    gpu_help.show();
  } else {
    gpu_help.hide();
  }
}

// Get the custom limits defined for the element (partition limit if defined, otherwise global or undefined)
function get_custom_limits(el) {
  const partition = get_partition_input().val();
  const partMin = el.attr(`min-${partition}`);
  const partMax = el.attr(`max-${partition}`);
  const origMin = el.data("orig-min");
  const origMax = el.data("orig-max");

  const min = partMin != null ? partMin : origMin;
  const max = partMax != null ? partMax : origMax;
  return [min, max];
}

// Update the min and max attributes of an input elements
function update_input(el) {
  // Use data-min and data-max to determine which slurm limit value to use
  const min = el.data("min");
  const max = el.data("max");

  const [customMin, customMax] = get_custom_limits(el);

  const parse = element_parse_function(el);

  const limits = get_current_limits();

  if (min != null || customMin != null) {
    let [limit, used, type] = get_limit(limits, min);
    if (customMin != null && (limit == null || parse(customMin) < parse(limit))) {
        limit = customMin;
        used = 0;
        type = "custom";
    }
    if (limit == null) {
      el.removeAttr("min");
      el.removeData("used");
      el.removeData("limit-type-min");
    } else {
      el.attr("min", limit);
      el.data("used", used);
      el.data("limit-type-min", type);
    }
  }
  if (max != null || customMax != null) {
    let [limit, used, type] = get_limit(limits, max);
    if (customMax != null && (limit == null || parse(customMax) < parse(limit))) {
        limit = customMax;
        used = 0;
        type = "custom";
    }
    if (limit == null) {
      el.removeAttr("max");
      el.removeData("used");
      el.removeData("limit-type-max");
    } else {
      el.attr("max", limit);
      el.data("used", used);
      el.data("limit-type-max", type);
    }
    if (limit === 0 && used === 0) {
      el.val(0);
      el.closest(".form-group").children().each(function() {$(this).hide()});
    } else {
      el.closest(".form-group").children().each(function() {$(this).show()});
    }
  }

  // Hide the csc_memory text element if max_mem_per_cpu is defined and add update memory amount in CPU help text.
  if (el.attr("id").endsWith("csc_memory")) {
    const group = el.closest(".form-group");
    const max_mem_cpu_help = $("#max_mem_per_cpu_help");

    const max_mem_per_cpu = limits["max_mem_per_cpu"];
    if (max_mem_per_cpu > 0) {
      const max_mem_cpu_help_amount = max_mem_cpu_help.find($("#max_mem_per_cpu_amount"));
      max_mem_cpu_help_amount.text(`${max_mem_per_cpu * 1024}M`)
      max_mem_cpu_help.show();
      group.children().each(function () {$(this).hide()});
    } else {
      max_mem_cpu_help.hide();
      group.children().each(function () {$(this).show()});
    }
  } else if (el.attr("id").endsWith("csc_cores")) {
    update_smt_help(limits);
  }
}

function update_smt_help(limits) {
    const cpu_smt_help = $("#cpu_smt_help");

    const threads_per_core = limits["threads_per_core"];
    if (threads_per_core > 1) {
      cpu_smt_help.find("#threads_per_core").text(threads_per_core);
      cpu_smt_help.show();
    } else {
      cpu_smt_help.hide();
    }

}

function get_limit(limits, name) {
  let limit = limits[name];
  let limit_type = "";
  let used = 0;

  if (limit == null) {
    return [null, 0, ""];
  }

  const qos = limits["qos"] || {};
  if (Object.keys(qos).length === 0) {
    return [limit, 0, ""];
  }

  const maxtres = qos["maxtres"];
  if (name in maxtres) {
    if (maxtres[name] < limit) {
      limit = maxtres[name];
      limit_type = "job";
    }
  }

  const maxtrespa = qos["maxtrespa"];
  if (name in maxtrespa) {
    const proj_jobs = slurm_submits["project"][get_project()] || {};
    const proj_used = proj_jobs[name] || 0;
    if (maxtrespa[name] - proj_used < limit) {
      limit = maxtrespa[name]- proj_used;
      used = proj_used;
      limit_type = "project";
    }
  }

  const maxtrespu = qos["maxtrespu"];
  if (name in maxtrespu) {
    const part_jobs = slurm_submits["partition"][get_partition()] || {};
    const part_used = part_jobs[name] || 0;
    if (maxtrespu[name] - part_used < limit) {
      limit = maxtrespu[name] - part_used;
      used = part_used;
      limit_type = "user";
    }
  }
  return [limit, used, limit_type];
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
  const submits = slurm_submits["numjobs"][proj_part] || 0;
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

// Convert number fields to int, time to int (seconds), use strings for the rest
// Returns a function for parsing the field
function element_parse_function(el) {
  if (el.attr("type") === "number") {
    return parseInt;
  } else if (el.data("type") === `time`) {
    return parse_time;
  } else {
    return (v) => v;
  }
}

// Check the validity of an input element
function validate_input(el) {
  if (!(el.attr("type") === "number" || el.attr("type") === "text")) {
    return;
  }

  if (el.is(":hidden")) {
    return;
  }

  // Values as strings, keep as is for formatting output
  const min = el.attr("min");
  const max = el.attr("max");
  const val = el.val();

  const parse = element_parse_function(el);

  const n_min = parse(min);
  const n_max = parse(max);
  const n_val = parse(val);

  if (el.attr("id").endsWith("csc_memory") && get_current_limits()["max_mem_per_cpu"] > 0) {
    setValidity(el, "");
  } else if (min != null && n_val < n_min) {
    const limit_type = el.data("limit-type-min");
    setValidity(el, `Value is less than the minimum ${limit_type == "custom" ? "allowed" : "for partition" } (${min})`);
  } else if (max != null && n_val > n_max) {
    const used = el.data("used") || 0;
    const limit_type = el.data("limit-type-max");
    const used_message = used > 0 ? `${used} used out of maximum ${n_max+used} per ${limit_type}` : `${max}`;
    setValidity(el, `Value exceeds the maximum ${limit_type == "custom" ? "allowed" : "for partition" } (${used_message})`);
    el.parent().addClass("form-group-invalid");
  } else {
    // Input element value ok (pattern/format is checked automatically)
    setValidity(el, "");
    el.parent().removeClass("form-group-invalid");
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


// Reset defaults button

function setup_reset_cache_button() {
  const reset_cache_field = $("#batch_connect_session_context_csc_reset_cache");
  if (reset_cache_field.length == 0) {
    return;
  }
  const form = reset_cache_field.parent();
  const reset_button = document.createElement("button");
  reset_button.className = "btn btn-secondary btn-block";
  reset_button.appendChild(document.createTextNode("Reset to default settings"));
  form.append(reset_button);
  $(reset_button).click(function(e) {
    e.preventDefault();
    const cache_file = reset_cache_field.data("app");
    deleteCache(cache_file);
  });
}

function deleteCache(cache_file) {
  const csrf_token = $("meta[name=csrf-token]").attr("content");
  if (cache_file == null) {
    console.warn("No app specified for reset form button");
    return;
  }
  $.ajax({url: "/pun/sys/dashboard/transfers.json",
    type: "POST",
    contentType: "text/plain",
    headers: {"X-CSRF-Token": csrf_token},
    data: JSON.stringify({"command": "rm", "files": [cache_file]}),
    success: () => {window.location.href = window.location.href}
  });
}

