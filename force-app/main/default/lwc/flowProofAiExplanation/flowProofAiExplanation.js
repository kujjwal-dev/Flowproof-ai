import { LightningElement, api } from "lwc";
import requestAiExplanation from "@salesforce/apex/FlowProofInvestigationController.requestAiExplanation";
import { errorMessage } from "c/flowProofFormat";

/**
 * AI explanation of a saved investigation. Hidden until there is an explanation to show or the
 * parent calls generate(); always marked as AI-generated.
 */
export default class FlowProofAiExplanation extends LightningElement {
  /** FlowProof_Investigation__c Id; explanations need a saved investigation. */
  @api investigationId;

  current;
  loading = false;
  error;

  /** Stored FlowProofAiExplanation from Apex, if any. */
  @api
  get explanation() {
    return this.current;
  }
  set explanation(value) {
    this.current = value;
    this.loading = false;
    this.error = undefined;
  }

  /**
   * Requests an explanation from the server.
   * @param {boolean} regenerate true to replace a stored explanation
   * @returns {Promise<void>} resolves when the request finishes
   */
  @api
  async generate(regenerate = false) {
    this.loading = true;
    this.error = undefined;
    try {
      this.current = await requestAiExplanation({
        investigationId: this.investigationId,
        regenerate
      });
    } catch (error) {
      this.error = errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  get visible() {
    return Boolean(this.current || this.loading || this.error);
  }

  get showExplanation() {
    return Boolean(this.current) && !this.loading;
  }

  get showRetry() {
    return !this.loading;
  }

  get retryLabel() {
    return this.current ? "Regenerate" : "Try again";
  }

  get points() {
    return this.toItems(
      ((this.current && this.current.keyPoints) || []).map(
        (point) => point.text
      ),
      "point"
    );
  }

  get hasPoints() {
    return this.points.length > 0;
  }

  get steps() {
    return this.toItems(this.current && this.current.nextSteps, "step");
  }

  get hasNextSteps() {
    return this.steps.length > 0;
  }

  toItems(values, prefix) {
    return (values || []).map((text, index) => ({
      key: `${prefix}-${index}`,
      text
    }));
  }

  handleRetry() {
    this.generate(Boolean(this.current));
  }
}
