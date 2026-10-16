import { LightningElement } from "lwc";
import getInvestigation from "@salesforce/apex/FlowProofInvestigationController.getInvestigation";
import { errorMessage } from "c/flowProofFormat";
import LOGO from "@salesforce/resourceUrl/FlowProofLogo";

const HIGHLIGHTS = [
  { label: "Evidence-labelled findings", icon: "utility:check" },
  { label: "Check all Flows at once", icon: "utility:list" },
  { label: "Flow health suggestions", icon: "utility:shield" },
  { label: "Plain-language AI explanations", icon: "utility:chat" }
];

/**
 * FlowProof AI workspace on the FlowProof AI app page: New investigation, History and Settings tabs.
 */
export default class FlowProofApp extends LightningElement {
  logoUrl = LOGO;
  highlights = HIGHLIGHTS;
  activeTab = "investigate";
  latestResult;
  latestSweep;
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
    this.latestSweep = undefined;
    this.latestResult = event.detail;
    this.refreshHistory();
  }

  handleSweepComplete(event) {
    this.latestResult = undefined;
    this.latestSweep = event.detail;
  }

  /** A full investigation opened from a sweep row: keep the sweep and show the result below it. */
  handleSweepInvestigation(event) {
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
