import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import runInvestigation from "@salesforce/apex/FlowProofInvestigationController.runInvestigation";
import simulateAllFlows from "@salesforce/apex/FlowProofInvestigationController.simulateAllFlows";
import {
  errorMessage,
  operatorLabel,
  outcomeInfo,
  overallInfo,
  triggerTypeLabel
} from "c/flowProofFormat";

const BLANK_CHOICE = { label: "(blank)", value: "" };

/**
 * Shows a "check all Flows" result (FlowProofSweepResult): one row per record-triggered Flow with
 * whether its entry conditions match the record now, the top finding and its health summary.
 * "Try different values" re-checks the Flows with simulated values (nothing is saved).
 * Investigate runs and saves a full investigation for that Flow and fires `investigationcomplete`
 * with the saved FlowProofInvestigationResult as detail.
 */
export default class FlowProofSweepResults extends LightningElement {
  current;
  displayed;
  showWhatIf = false;
  draft = {};
  whatIfError;
  running = false;
  runError;

  /** FlowProofSweepResult from Apex: the check against the record's current values. */
  @api
  get sweep() {
    return this.current;
  }
  set sweep(value) {
    this.current = value;
    this.displayed = value;
    this.showWhatIf = false;
    this.draft = {};
    this.whatIfError = undefined;
    this.runError = undefined;
  }

  get simulated() {
    return Boolean(this.displayed && this.displayed.simulated);
  }

  get simulatedText() {
    const changes = this.displayed.simulatedChanges || [];
    return changes.length ? changes.join("; ") : "no values changed.";
  }

  get canSimulate() {
    return (this.current.whatIfFields || []).length > 0;
  }

  get canInvestigate() {
    return !this.simulated;
  }

  get whatIfButtonLabel() {
    return this.showWhatIf ? "Hide what-if" : "Try different values";
  }

  get title() {
    const record = this.displayed.recordName || this.displayed.recordId;
    return `All Flows on ${this.displayed.objectApiName}: ${record}`;
  }

  get noticeText() {
    return this.simulated
      ? "Based on the simulated values above. The record was not changed."
      : "Quick check against the record's current values; not saved and not proof that a Flow ran. Use Investigate for a full, saved result.";
  }

  get whatIfInputs() {
    return (this.current.whatIfFields || []).map((field) => {
      const draft = this.draftValue(field);
      return {
        ...field,
        draft,
        checked: draft === "true",
        isPicklist: field.inputType === "picklist",
        isCheckbox: field.inputType === "checkbox",
        choices: [BLANK_CHOICE, ...(field.options || [])]
      };
    });
  }

  get rows() {
    const valueWord = this.simulated ? "value" : "current value";
    return (this.displayed.rows || []).map((row) => ({
      ...row,
      inactive: !row.isActive,
      triggerText: triggerTypeLabel(row.triggerType),
      overall: overallInfo(row.overallCode),
      conditions: (row.unmatchedConditions || []).map((condition) => ({
        key: `${row.flowApiName}-${condition.index}`,
        text: `${condition.field} ${operatorLabel(condition.operator).toLowerCase()} ${condition.expectedDisplay}: ${outcomeInfo(condition.outcomeCode).label.toLowerCase()} (${valueWord}: ${condition.actualDisplay})`
      })),
      healthText: this.healthText(row),
      healthTitle: row.topHealthFinding ? row.topHealthFinding.title : ""
    }));
  }

  get hasRows() {
    return (this.displayed.rows || []).length > 0;
  }

  get summaryText() {
    const rows = this.displayed.rows || [];
    const matching = rows.filter(
      (row) => row.isActive && row.overallCode === "SATISFIED"
    ).length;
    const notMatching = rows.filter(
      (row) => row.overallCode === "NOT_SATISFIED"
    ).length;
    const target = this.simulated ? "these values" : "the record now";
    const checked = `Checked ${rows.length} of ${this.displayed.flowCount} record-triggered Flows.`;
    return `${checked} ${matching} active ${matching === 1 ? "Flow's" : "Flows'"} conditions match ${target}; ${notMatching} do not.`;
  }

  get hasSkipped() {
    return (this.displayed.skippedFlowLabels || []).length > 0;
  }

  get skippedText() {
    const skipped = this.displayed.skippedFlowLabels || [];
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

  draftValue(field) {
    if (Object.prototype.hasOwnProperty.call(this.draft, field.apiName)) {
      return this.draft[field.apiName];
    }
    if (field.inputType === "checkbox") {
      return field.value === "true" ? "true" : "false";
    }
    return field.value || "";
  }

  /** @returns {Object<string, string>} only the values the user changed */
  changedValues() {
    const changed = {};
    (this.current.whatIfFields || []).forEach((field) => {
      const original =
        field.inputType === "checkbox"
          ? String(field.value === "true")
          : field.value || "";
      const draft = this.draftValue(field);
      if (draft !== original) {
        changed[field.apiName] = draft;
      }
    });
    return changed;
  }

  handleToggleWhatIf() {
    this.showWhatIf = !this.showWhatIf;
  }

  handleWhatIfChange(event) {
    const apiName = event.target.dataset.field;
    const field = (this.current.whatIfFields || []).find(
      (candidate) => candidate.apiName === apiName
    );
    const value =
      field && field.inputType === "checkbox"
        ? String(Boolean(event.detail.checked))
        : (event.detail.value ?? "");
    this.draft = { ...this.draft, [apiName]: value };
    this.whatIfError = undefined;
  }

  handleShowCurrent() {
    this.displayed = this.current;
  }

  async handleSimulate() {
    const values = this.changedValues();
    if (!Object.keys(values).length) {
      this.whatIfError = "Change at least one value first.";
      return;
    }
    this.running = true;
    this.whatIfError = undefined;
    try {
      this.displayed = await simulateAllFlows({
        objectApiName: this.current.objectApiName,
        recordId: this.current.recordId,
        values
      });
    } catch (error) {
      this.whatIfError = errorMessage(error);
    } finally {
      this.running = false;
    }
  }

  async handleInvestigate(event) {
    const flowApiName = event.target.dataset.flow;
    this.running = true;
    this.runError = undefined;
    try {
      const result = await runInvestigation({
        objectApiName: this.current.objectApiName,
        recordId: this.current.recordId,
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
