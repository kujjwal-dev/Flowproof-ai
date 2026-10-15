import { LightningElement } from "lwc";
import getInvestigation from "@salesforce/apex/FlowProofInvestigationController.getInvestigation";
import { errorMessage } from "c/flowProofFormat";

/**
 * FlowProof AI workspace on the FlowProof AI app page: New investigation, History and Settings tabs.
 */
export default class FlowProofApp extends LightningElement {
  activeTab = "investigate";
  latestResult;
  viewedResult;
  viewLoading = false;
  viewError;

  handleTabActive(event) {
    this.activeTab = event.target.value;
    if (this.activeTab === "history") {
      this.refreshHistory();
    }
  }

  handleInvestigationComplete(event) {
    this.latestResult = event.detail;
    this.refreshHistory();
  }

  async handleViewInvestigation(event) {
    this.viewLoading = true;
    this.viewError = undefined;
    try {
      this.viewedResult = await getInvestigation({
        investigationId: event.detail.investigationId
      });
    } catch (error) {
      this.viewError = errorMessage(error);
    } finally {
      this.viewLoading = false;
    }
  }

  handleBackToHistory() {
    this.viewedResult = undefined;
    this.refreshHistory();
  }

  refreshHistory() {
    const history = this.template.querySelector("c-flow-proof-history");
    if (history) {
      history.refresh();
    }
  }
}
