import { LightningElement, wire } from "lwc";
import getSettings from "@salesforce/apex/FlowProofInvestigationController.getSettings";
import testConnection from "@salesforce/apex/FlowProofInvestigationController.testConnection";
import { errorMessage } from "c/flowProofFormat";

const HEADLINES = {
  CONNECTED: "Connected",
  NOT_AUTHORIZED: "Not authorized",
  NOT_CONFIGURED: "Not set up",
  UNAVAILABLE: "Temporarily unavailable"
};

/**
 * Shows FlowProof settings and lets the user test the FlowProof_Org_API connection.
 */
export default class FlowProofSettings extends LightningElement {
  settings;
  settingsError;
  connection;
  connectionError;
  testing = false;

  @wire(getSettings)
  wiredSettings({ data, error }) {
    if (data) {
      this.settings = data;
      this.settingsError = undefined;
    } else if (error) {
      this.settings = undefined;
      this.settingsError = errorMessage(error);
    }
  }

  get aiStatus() {
    return this.settings && this.settings.aiEnabled ? "On" : "Off";
  }

  get aiModel() {
    return (this.settings && this.settings.aiModel) || "Not set";
  }

  get connectionHeadline() {
    return this.connection
      ? HEADLINES[this.connection.status] || this.connection.status
      : "";
  }

  get connectionIcon() {
    return this.connection && this.connection.connected
      ? "utility:success"
      : "utility:error";
  }

  get connectionIconVariant() {
    return this.connection && this.connection.connected ? "success" : "error";
  }

  async handleTestConnection() {
    this.testing = true;
    this.connectionError = undefined;
    try {
      this.connection = await testConnection();
    } catch (error) {
      this.connection = undefined;
      this.connectionError = errorMessage(error);
    } finally {
      this.testing = false;
    }
  }
}
