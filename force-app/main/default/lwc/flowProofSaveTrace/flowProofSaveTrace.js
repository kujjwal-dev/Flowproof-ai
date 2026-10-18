import { LightningElement, api } from "lwc";
import startSaveTrace from "@salesforce/apex/FlowProofInvestigationController.startSaveTrace";
import readSaveTrace from "@salesforce/apex/FlowProofInvestigationController.readSaveTrace";
import stopSaveTrace from "@salesforce/apex/FlowProofInvestigationController.stopSaveTrace";
import { errorMessage } from "c/flowProofFormat";

const STATUS = {
  FINISHED: { label: "Ran", badgeClass: "slds-theme_success" },
  FAILED: { label: "Failed", badgeClass: "slds-theme_error" },
  STARTED: { label: "Started", badgeClass: "slds-theme_warning" }
};

/**
 * "Record a test save": switches on a debug log for the user, waits for them to save the record,
 * then shows which record-triggered Flows really ran on that save. FlowProof never saves the record.
 */
export default class FlowProofSaveTrace extends LightningElement {
  /** The record to watch. */
  @api recordId;

  session;
  trace;
  notFoundMessage;
  busy = false;
  error;

  get isIdle() {
    return !this.session && !this.trace;
  }

  get isRecording() {
    return Boolean(this.session) && !this.trace;
  }

  get isDone() {
    return Boolean(this.trace);
  }

  get runs() {
    return (this.trace.ran || []).map((run, index) => ({
      key: `run-${index}`,
      label: run.label,
      status: STATUS[run.statusCode] || STATUS.STARTED,
      hasElements: (run.elements || []).length > 0,
      elementsText: (run.elements || []).join(", "),
      hasOutcomes: (run.outcomes || []).length > 0,
      outcomesText: (run.outcomes || []).join(", "),
      errorItems: (run.errors || []).map((text, errorIndex) => ({
        key: `error-${index}-${errorIndex}`,
        text
      }))
    }));
  }

  get hasRuns() {
    return (this.trace.ran || []).length > 0;
  }

  get hasNotStarted() {
    return (this.trace.notStarted || []).length > 0;
  }

  get notStartedText() {
    return this.trace.notStarted.join(", ");
  }

  get hasValidationFailures() {
    return (this.trace.validationFailures || []).length > 0;
  }

  get validationText() {
    return this.trace.validationFailures.join("; ");
  }

  get doneNote() {
    const matched =
      this.trace.matchedBy === "SAVE_TIME"
        ? "Matched to this record by its save time, because no Flow ran for it."
        : "From the debug log of this save.";
    const logging = this.trace.loggingStopped
      ? " Logging is off again."
      : " Logging switches itself off within 30 minutes.";
    return `${matched} Scheduled and asynchronous paths run later and are not included.${logging}`;
  }

  async handleStart() {
    this.busy = true;
    this.error = undefined;
    try {
      this.trace = undefined;
      this.notFoundMessage = undefined;
      this.session = await startSaveTrace({ recordId: this.recordId });
    } catch (error) {
      this.session = undefined;
      this.error = errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  async handleRead() {
    this.busy = true;
    this.error = undefined;
    try {
      const trace = await readSaveTrace({ session: this.session });
      if (trace.logFound) {
        this.trace = trace;
        this.session = undefined;
      } else {
        this.notFoundMessage = trace.message;
      }
    } catch (error) {
      this.error = errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  async handleCancel() {
    this.busy = true;
    this.error = undefined;
    try {
      await stopSaveTrace({ session: this.session });
      this.session = undefined;
      this.notFoundMessage = undefined;
    } catch (error) {
      this.error = errorMessage(error);
    } finally {
      this.busy = false;
    }
  }
}
