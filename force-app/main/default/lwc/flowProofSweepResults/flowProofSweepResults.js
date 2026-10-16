import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import runInvestigation from "@salesforce/apex/FlowProofInvestigationController.runInvestigation";
import {
  errorMessage,
  operatorLabel,
  outcomeInfo,
  overallInfo,
  triggerTypeLabel
} from "c/flowProofFormat";

/**
 * Shows a "check all Flows" result (FlowProofSweepResult): one row per record-triggered Flow with
 * whether its entry conditions match the record now, the top finding and its health summary.
 * Investigate runs and saves a full investigation for that Flow and fires `investigationcomplete`
 * with the saved FlowProofInvestigationResult as detail.
 */
export default class FlowProofSweepResults extends LightningElement {
  /** FlowProofSweepResult from Apex. */
  @api sweep;

  running = false;
  runError;

  get title() {
    const record = this.sweep.recordName || this.sweep.recordId;
    return `All Flows on ${this.sweep.objectApiName}: ${record}`;
  }

  get rows() {
    return (this.sweep.rows || []).map((row) => ({
      ...row,
      inactive: !row.isActive,
      triggerText: triggerTypeLabel(row.triggerType),
      overall: overallInfo(row.overallCode),
      conditions: (row.unmatchedConditions || []).map((condition) => ({
        key: `${row.flowApiName}-${condition.index}`,
        text: `${condition.field} ${operatorLabel(condition.operator).toLowerCase()} ${condition.expectedDisplay}: ${outcomeInfo(condition.outcomeCode).label.toLowerCase()} (current value: ${condition.actualDisplay})`
      })),
      healthText: this.healthText(row),
      healthTitle: row.topHealthFinding ? row.topHealthFinding.title : ""
    }));
  }

  get hasRows() {
    return (this.sweep.rows || []).length > 0;
  }

  get summaryText() {
    const rows = this.sweep.rows || [];
    const matching = rows.filter(
      (row) => row.isActive && row.overallCode === "SATISFIED"
    ).length;
    const notMatching = rows.filter(
      (row) => row.overallCode === "NOT_SATISFIED"
    ).length;
    const checked = `Checked ${rows.length} of ${this.sweep.flowCount} record-triggered Flows.`;
    return `${checked} ${matching} active ${matching === 1 ? "Flow's" : "Flows'"} conditions match the record now; ${notMatching} do not.`;
  }

  get hasSkipped() {
    return (this.sweep.skippedFlowLabels || []).length > 0;
  }

  get skippedText() {
    const skipped = this.sweep.skippedFlowLabels || [];
    return `Not checked (limit reached): ${skipped.join(", ")}. Investigate them one at a time.`;
  }

  healthText(row) {
    if (!row.healthChecked) {
      return "Not checked";
    }
    if (!row.healthCount) {
      return "No issues found";
    }
    return row.healthCount === 1
      ? "1 suggestion"
      : `${row.healthCount} suggestions`;
  }

  async handleInvestigate(event) {
    const flowApiName = event.target.dataset.flow;
    this.running = true;
    this.runError = undefined;
    try {
      const result = await runInvestigation({
        objectApiName: this.sweep.objectApiName,
        recordId: this.sweep.recordId,
        flowApiName,
        expectedOutcome: null
      });
      this.dispatchEvent(
        new CustomEvent("investigationcomplete", { detail: result })
      );
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Investigation complete",
          message: `${result.investigationName} was saved.`,
          variant: "success"
        })
      );
    } catch (error) {
      this.runError = errorMessage(error);
    } finally {
      this.running = false;
    }
  }
}
