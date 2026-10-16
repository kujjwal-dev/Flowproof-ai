import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getObjectOptions from "@salesforce/apex/FlowProofInvestigationController.getObjectOptions";
import getFlows from "@salesforce/apex/FlowProofInvestigationController.getFlows";
import runInvestigation from "@salesforce/apex/FlowProofInvestigationController.runInvestigation";
import checkAllFlows from "@salesforce/apex/FlowProofInvestigationController.checkAllFlows";
import { errorMessage, flowOptionLabel } from "c/flowProofFormat";

/** Flow picker value that checks every record-triggered Flow on the object. */
const ALL_FLOWS = "__ALL_FLOWS__";

/**
 * Form for starting an investigation: object, record, Flow and optional expected outcome.
 * Fires `investigationcomplete` with the saved FlowProofInvestigationResult as detail, or, when
 * "All Flows" is chosen, `sweepcomplete` with the unsaved FlowProofSweepResult as detail.
 */
export default class FlowProofNewInvestigation extends LightningElement {
  objectApiName;
  recordId;
  flowApiName;
  expectedOutcome = "";

  objectOptions = [];
  objectsLoaded = false;
  objectsError;
  flowOptions = [];
  flowsError;
  running = false;
  runError;

  @wire(getObjectOptions)
  wiredObjects({ data, error }) {
    if (data) {
      this.objectOptions = data.map((option) => ({
        label: `${option.label} (${option.flowCount} ${option.flowCount === 1 ? "Flow" : "Flows"})`,
        value: option.apiName
      }));
      this.objectsError = undefined;
      this.objectsLoaded = true;
    } else if (error) {
      this.objectOptions = [];
      this.objectsError = errorMessage(error);
      this.objectsLoaded = true;
    }
  }

  @wire(getFlows, { objectApiName: "$objectApiName" })
  wiredFlows({ data, error }) {
    if (data) {
      const flows = data.map((flow) => ({
        label: flowOptionLabel(flow),
        value: flow.apiName
      }));
      this.flowOptions = flows.length
        ? [
            {
              label: `All Flows on this object (quick check of ${flows.length})`,
              value: ALL_FLOWS
            },
            ...flows
          ]
        : [];
      this.flowsError = undefined;
    } else if (error) {
      this.flowOptions = [];
      this.flowsError = errorMessage(error);
    }
  }

  get objectsLoading() {
    return !this.objectsLoaded;
  }

  get showNoObjects() {
    return (
      this.objectsLoaded &&
      !this.objectsError &&
      this.objectOptions.length === 0
    );
  }

  get showForm() {
    return (
      this.objectsLoaded && !this.objectsError && this.objectOptions.length > 0
    );
  }

  /** One-element list so the record picker is recreated when the object changes. */
  get pickerObjects() {
    return this.objectApiName ? [this.objectApiName] : [];
  }

  get noObjectChosen() {
    return !this.objectApiName;
  }

  get flowPickerDisabled() {
    return !this.objectApiName || this.flowOptions.length === 0;
  }

  get flowPlaceholder() {
    if (!this.objectApiName) {
      return "Choose an object first";
    }
    return this.flowOptions.length
      ? "Choose a Flow"
      : "No record-triggered Flows on this object";
  }

  get isAllFlows() {
    return this.flowApiName === ALL_FLOWS;
  }

  get showExpectedOutcome() {
    return !this.isAllFlows;
  }

  get runLabel() {
    return this.isAllFlows ? "Check all Flows" : "Investigate";
  }

  get runIcon() {
    return this.isAllFlows ? "utility:list" : "utility:search";
  }

  get cannotInvestigate() {
    return (
      this.running || !this.objectApiName || !this.recordId || !this.flowApiName
    );
  }

  handleObjectChange(event) {
    this.objectApiName = event.detail.value;
    this.recordId = undefined;
    this.flowApiName = undefined;
    this.flowOptions = [];
    this.runError = undefined;
  }

  handleRecordChange(event) {
    this.recordId = event.detail.recordId || undefined;
    this.runError = undefined;
  }

  handleFlowChange(event) {
    this.flowApiName = event.detail.value;
    this.runError = undefined;
  }

  handleOutcomeChange(event) {
    this.expectedOutcome = event.detail.value;
  }

  async handleInvestigate() {
    if (this.cannotInvestigate) {
      return;
    }
    this.running = true;
    this.runError = undefined;
    if (this.isAllFlows) {
      await this.runSweep();
      return;
    }
    try {
      const result = await runInvestigation({
        objectApiName: this.objectApiName,
        recordId: this.recordId,
        flowApiName: this.flowApiName,
        expectedOutcome: this.expectedOutcome || null
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

  async runSweep() {
    try {
      const sweep = await checkAllFlows({
        objectApiName: this.objectApiName,
        recordId: this.recordId
      });
      this.dispatchEvent(new CustomEvent("sweepcomplete", { detail: sweep }));
    } catch (error) {
      this.runError = errorMessage(error);
    } finally {
      this.running = false;
    }
  }
}
