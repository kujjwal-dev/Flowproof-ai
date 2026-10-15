/**
 * Shared display rules for FlowProof AI components: labels, badge styles and icons for evidence
 * categories, severities, condition outcomes and overall results, plus small formatting helpers.
 * Keeping them in one module makes every screen describe evidence the same way.
 */

const CATEGORY = {
  CONFIRMED: {
    label: "Confirmed by evidence",
    badgeClass: "slds-theme_success"
  },
  SUPPORTED_HYPOTHESIS: {
    label: "Supported hypothesis",
    badgeClass: "slds-theme_warning"
  },
  INSUFFICIENT_EVIDENCE: {
    label: "Insufficient evidence",
    badgeClass: "slds-badge_lightest"
  },
  UNSUPPORTED: {
    label: "Unsupported analysis",
    badgeClass: "slds-badge_inverse"
  }
};

const SEVERITY = {
  HIGH: { label: "High", iconName: "utility:error", iconVariant: "error" },
  MEDIUM: {
    label: "Medium",
    iconName: "utility:warning",
    iconVariant: "warning"
  },
  LOW: { label: "Low", iconName: "utility:info", iconVariant: "" },
  INFO: { label: "Info", iconName: "utility:info_alt", iconVariant: "" }
};

const OUTCOME = {
  MATCH: { label: "Match", badgeClass: "slds-theme_success" },
  NO_MATCH: { label: "No match", badgeClass: "slds-theme_error" },
  UNCERTAIN: { label: "Uncertain", badgeClass: "slds-theme_warning" },
  UNSUPPORTED: { label: "Not evaluated", badgeClass: "slds-badge_inverse" },
  INACCESSIBLE: { label: "No access", badgeClass: "slds-badge_lightest" },
  MISSING: { label: "Missing field", badgeClass: "slds-theme_error" }
};

const OVERALL = {
  SATISFIED: { label: "Conditions met", badgeClass: "slds-theme_success" },
  NOT_SATISFIED: {
    label: "Conditions not met",
    badgeClass: "slds-theme_error"
  },
  INDETERMINATE: { label: "Indeterminate", badgeClass: "slds-theme_warning" },
  NOT_EVALUATED: { label: "Not evaluated", badgeClass: "slds-badge_lightest" }
};

const OPERATOR = {
  equalto: "Equals",
  notequalto: "Does not equal",
  greaterthan: "Greater than",
  lessthan: "Less than",
  greaterthanorequalto: "At least",
  lessthanorequalto: "At most",
  isnull: "Is null"
};

const TRIGGER_TYPE = {
  RecordBeforeSave: "Before save (fast field updates)",
  RecordAfterSave: "After save",
  RecordBeforeDelete: "Before delete",
  Scheduled: "Scheduled",
  PlatformEvent: "Platform event"
};

const RECORD_TRIGGER_TYPE = {
  Create: "A record is created",
  Update: "A record is updated",
  CreateAndUpdate: "A record is created or updated",
  Delete: "A record is deleted"
};

const UNKNOWN = { label: "Unknown", badgeClass: "slds-badge_lightest" };

/**
 * @param {string} category FlowProofFinding.Category name
 * @returns {{label: string, badgeClass: string}}
 */
export function categoryInfo(category) {
  return CATEGORY[category] || UNKNOWN;
}

/**
 * @param {string} severity FlowProofFinding.Severity name
 * @returns {{label: string, iconName: string, iconVariant: string}}
 */
export function severityInfo(severity) {
  return SEVERITY[severity] || SEVERITY.INFO;
}

/**
 * @param {string} outcome condition outcome name
 * @returns {{label: string, badgeClass: string}}
 */
export function outcomeInfo(outcome) {
  return OUTCOME[outcome] || UNKNOWN;
}

/**
 * @param {string} overall overall result name (SATISFIED, NOT_SATISFIED, INDETERMINATE, NOT_EVALUATED)
 * @returns {{label: string, badgeClass: string}}
 */
export function overallInfo(overall) {
  return OVERALL[overall || "NOT_EVALUATED"] || UNKNOWN;
}

/**
 * @param {string} operator FlowRecordFilterOperator name
 * @returns {string} readable operator
 */
export function operatorLabel(operator) {
  return OPERATOR[(operator || "").toLowerCase()] || operator || "";
}

/**
 * @param {string} triggerType FlowDefinitionView trigger type
 * @returns {string} readable trigger type
 */
export function triggerTypeLabel(triggerType) {
  return TRIGGER_TYPE[triggerType] || triggerType || "Not triggered by records";
}

/**
 * @param {string} recordTriggerType Create, Update, CreateAndUpdate or Delete
 * @returns {string} readable trigger event
 */
export function recordTriggerTypeLabel(recordTriggerType) {
  return RECORD_TRIGGER_TYPE[recordTriggerType] || recordTriggerType || "";
}

/**
 * Label for a Flow in the Flow picker, e.g. "Opportunity Onboarding (Active, after save)".
 * @param {{label: string, isActive: boolean, activeVersionId: string, triggerType: string}} flow Flow summary
 * @returns {string} option label
 */
export function flowOptionLabel(flow) {
  const state = flow.activeVersionId ? "Active" : "Inactive";
  const trigger = (
    TRIGGER_TYPE[flow.triggerType] ||
    flow.triggerType ||
    ""
  ).toLowerCase();
  return trigger
    ? `${flow.label} (${state}, ${trigger})`
    : `${flow.label} (${state})`;
}

/**
 * Turns an Apex, LDS or JavaScript error into a readable message.
 * @param {*} error error from a wire, an imperative call or JavaScript
 * @returns {string} message
 */
export function errorMessage(error) {
  if (!error) {
    return "";
  }
  if (Array.isArray(error.body)) {
    return error.body.map((entry) => entry.message).join(" ");
  }
  if (error.body && typeof error.body.message === "string") {
    return error.body.message;
  }
  if (typeof error.message === "string") {
    return error.message;
  }
  return "Something went wrong.";
}
