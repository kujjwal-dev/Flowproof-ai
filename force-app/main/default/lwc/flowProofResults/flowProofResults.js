import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getSettings from "@salesforce/apex/FlowProofInvestigationController.getSettings";
import {
  operatorLabel,
  outcomeInfo,
  overallInfo,
  recordTriggerTypeLabel,
  triggerTypeLabel
} from "c/flowProofFormat";

// Shown once, as the note under the Results header, instead of as a finding.
const EXECUTION_NOT_CONFIRMED = "EXECUTION_NOT_CONFIRMED";
// Outcomes whose meaning is clear from the table; others get their reason as a note.
const SELF_EXPLANATORY = new Set(["MATCH", "NO_MATCH"]);

/**
 * Displays one FlowProofInvestigationResult: overall outcome, the "execution not confirmed"
 * notice, findings with evidence categories and next steps, the optional AI explanation, the
 * condition table, Flow health suggestions and Flow settings.
 */
export default class FlowProofResults extends NavigationMixin(
  LightningElement
) {
  /** FlowProofInvestigationResult from Apex. */
  @api result;

  aiEnabled = false;
  explainRequestedId;

  @wire(getSettings)
  wiredSettings({ data }) {
    if (data) {
      this.aiEnabled = data.aiEnabled === true;
    }
  }

  get canExplain() {
    return (
      this.aiEnabled &&
      Boolean(this.result.investigationId) &&
      !this.result.aiExplanation &&
      this.explainRequestedId !== this.result.investigationId
    );
  }

  get title() {
    const name = this.result.investigationName
      ? `${this.result.investigationName}: `
      : "";
    return `${name}${this.flowLabel}`;
  }

  get recordLabel() {
    return this.result.recordName || this.result.recordId;
  }

  get flowLabel() {
    return this.result.flow ? this.result.flow.label : "Unknown Flow";
  }

  get overall() {
    const overall = this.result.evaluation
      ? this.result.evaluation.overallCode
      : "NOT_EVALUATED";
    return overallInfo(overall);
  }

  get displayedFindings() {
    return (this.result.findings || []).filter(
      (finding) => finding.ruleCode !== EXECUTION_NOT_CONFIRMED
    );
  }

  get findingCount() {
    return this.displayedFindings.length;
  }

  get healthFindings() {
    return this.result.healthFindings || [];
  }

  get healthCount() {
    return this.healthFindings.length;
  }

  get healthEmptyText() {
    return this.result.healthChecked
      ? "FlowProof's checks found no design issues in this Flow version."
      : "Flow health was not checked: FlowProof could not read the Flow's full definition.";
  }

  get hasConditions() {
    return Boolean(
      this.result.evaluation && (this.result.evaluation.conditions || []).length
    );
  }

  get overallReason() {
    return this.result.evaluation ? this.result.evaluation.overallReason : "";
  }

  get conditions() {
    if (!this.result.evaluation) {
      return [];
    }
    return (this.result.evaluation.conditions || []).map((condition) => ({
      ...condition,
      key: `condition-${condition.index}`,
      operatorText: operatorLabel(condition.operator),
      actualText:
        condition.actualDisplay === undefined ||
        condition.actualDisplay === null
          ? "Not read"
          : condition.actualDisplay,
      outcomeInfo: outcomeInfo(condition.outcomeCode),
      note: SELF_EXPLANATORY.has(condition.outcomeCode) ? "" : condition.reason
    }));
  }

  get noConditionsText() {
    if (this.result.evaluation) {
      return this.result.evaluation.overallReason;
    }
    if (this.result.conditionsRead) {
      return "The conditions were not evaluated for this record. See the findings above.";
    }
    return "The Flow's entry conditions could not be read. See the findings above.";
  }

  get flowStatus() {
    const flow = this.result.flow;
    if (!flow) {
      return "Unknown";
    }
    return flow.activeVersionId ? "Active" : "No active version";
  }

  get triggerText() {
    const flow = this.result.flow;
    if (!flow) {
      return "Unknown";
    }
    const event = recordTriggerTypeLabel(
      this.result.recordTriggerType || flow.recordTriggerType
    );
    return event
      ? `${triggerTypeLabel(flow.triggerType)}: ${event}`
      : triggerTypeLabel(flow.triggerType);
  }

  get triggerObjectText() {
    return (
      this.result.triggerObject ||
      (this.result.flow && this.result.flow.triggerObjectLabel) ||
      "Unknown"
    );
  }

  get onlyWhenUpdatedText() {
    if (!this.result.conditionsRead) {
      return "Unknown";
    }
    return this.result.runsOnlyWhenUpdatedToMeetConditions ? "Yes" : "No";
  }

  handleExplain() {
    this.explainRequestedId = this.result.investigationId;
    this.template.querySelector("c-flow-proof-ai-explanation").generate(false);
  }

  handleOpenRecord() {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: this.result.recordId,
        objectApiName: this.result.objectApiName,
        actionName: "view"
      }
    });
  }
}
