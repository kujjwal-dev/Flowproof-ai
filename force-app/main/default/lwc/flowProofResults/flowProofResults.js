import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import {
  categoryInfo,
  operatorLabel,
  outcomeInfo,
  overallInfo,
  recordTriggerTypeLabel,
  severityInfo,
  triggerTypeLabel
} from "c/flowProofFormat";

/**
 * Displays one FlowProofInvestigationResult: overall outcome, the "execution not confirmed"
 * notice, findings with evidence categories and next steps, the condition table and Flow settings.
 */
export default class FlowProofResults extends NavigationMixin(
  LightningElement
) {
  /** FlowProofInvestigationResult from Apex. */
  @api result;

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

  get findings() {
    return (this.result.findings || []).map((finding, index) => {
      const severity = severityInfo(finding.severityCode);
      return {
        ...finding,
        key: `${finding.ruleCode}-${index}`,
        severity,
        severityText: `${severity.label} severity`,
        categoryInfo: categoryInfo(finding.categoryCode)
      };
    });
  }

  get findingCount() {
    return (this.result.findings || []).length;
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
      outcomeInfo: outcomeInfo(condition.outcomeCode)
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
