import { LightningElement, api } from "lwc";
import { categoryInfo, severityInfo } from "c/flowProofFormat";

/**
 * Lists FlowProofFinding objects with severity icon, evidence category, detail and next step.
 * Used for diagnostic findings and Flow health findings alike.
 */
export default class FlowProofFindingList extends LightningElement {
  /** FlowProofFinding objects from Apex, most important first. */
  @api findings;
  /** Shown when there are no findings. */
  @api emptyText = "No findings.";
  /** Label before each recommendation. */
  @api nextStepLabel = "Next step:";

  get hasFindings() {
    return (this.findings || []).length > 0;
  }

  get items() {
    return (this.findings || []).map((finding, index) => {
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
}
