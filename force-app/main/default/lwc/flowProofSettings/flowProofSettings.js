import { LightningElement, wire } from "lwc";
import getSettings from "@salesforce/apex/FlowProofInvestigationController.getSettings";
import testConnection from "@salesforce/apex/FlowProofInvestigationController.testConnection";
import testAiConnection from "@salesforce/apex/FlowProofInvestigationController.testAiConnection";
import { errorMessage } from "c/flowProofFormat";

const HEADLINES = {
  CONNECTED: "Connected",
  NOT_AUTHORIZED: "Not authorized",
  NOT_CONFIGURED: "Not set up",
  UNAVAILABLE: "Temporarily unavailable"
};

/**
 * @param {{status: string, connected: boolean}} connection FlowProofConnectionStatus
 * @returns {{headline: string, icon: string, variant: string}} how to show it
 */
function connectionView(connection) {
  if (!connection) {
    return { headline: "", icon: "utility:error", variant: "error" };
  }
  return {
    headline: HEADLINES[connection.status] || connection.status,
    icon: connection.connected ? "utility:success" : "utility:error",
    variant: connection.connected ? "success" : "error"
  };
}

/**
 * Shows FlowProof settings and lets the user test the org API and Gemini connections.
 */
export default class FlowProofSettings extends LightningElement {
  settings;
  settingsError;
  connection;
  connectionError;
  testing = false;
  aiConnection;
  aiConnectionError;
  aiTesting = false;

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

  get aiValuesText() {
    return this.settings && this.settings.aiSendFieldValues
      ? "Yes, field values are sent"
      : "No, field values are hidden";
  }

  get connectionHeadline() {
    return connectionView(this.connection).headline;
  }

  get connectionIcon() {
    return connectionView(this.connection).icon;
  }

  get connectionIconVariant() {
    return connectionView(this.connection).variant;
  }

  get aiConnectionView() {
    return connectionView(this.aiConnection);
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

  async handleTestAiConnection() {
    this.aiTesting = true;
    this.aiConnectionError = undefined;
    try {
      this.aiConnection = await testAiConnection();
    } catch (error) {
      this.aiConnection = undefined;
      this.aiConnectionError = errorMessage(error);
    } finally {
      this.aiTesting = false;
    }
  }
}
