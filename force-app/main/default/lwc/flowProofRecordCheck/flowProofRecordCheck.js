import { LightningElement, api } from "lwc";
import checkAllFlows from "@salesforce/apex/FlowProofInvestigationController.checkAllFlows";
import { errorMessage } from "c/flowProofFormat";

/**
 * "Automation check" for a record page or quick action: checks every record-triggered Flow on the
 * record's object against this record when the user asks (each check reads the Flow definitions,
 * so it never runs on page load). A full investigation opens below the list.
 */
export default class FlowProofRecordCheck extends LightningElement {
  /** Set by the record page or quick action. */
  @api recordId;
  /** Set by the record page; derived from recordId by Apex when missing (quick actions). */
  @api objectApiName;

  sweep;
  result;
  running = false;
  error;

  async handleCheck() {
    this.running = true;
    this.error = undefined;
    try {
      this.sweep = await checkAllFlows({
        objectApiName: this.objectApiName || null,
        recordId: this.recordId
      });
    } catch (error) {
      this.error = errorMessage(error);
    } finally {
      this.running = false;
    }
  }

  handleInvestigationComplete(event) {
    this.result = event.detail;
  }
}
