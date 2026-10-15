import { createElement } from "lwc";
import FlowProofSettings from "c/flowProofSettings";
import getSettings from "@salesforce/apex/FlowProofInvestigationController.getSettings";
import testConnection from "@salesforce/apex/FlowProofInvestigationController.testConnection";

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getSettings",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.testConnection",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render() {
  const element = createElement("c-flow-proof-settings", {
    is: FlowProofSettings
  });
  document.body.appendChild(element);
  return element;
}

describe("c-flow-proof-settings", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows AI explanations as off with the configured model", async () => {
    const element = render();
    getSettings.emit({ aiEnabled: false, aiModel: "gemini-3.8-flash" });
    await flushPromises();

    expect(element.shadowRoot.querySelector(".ai-status").textContent).toBe(
      "Off"
    );
    expect(
      element.shadowRoot.querySelector(".settings-list").textContent
    ).toContain("gemini-3.8-flash");
  });

  it("reports a working connection", async () => {
    testConnection.mockResolvedValue({
      connected: true,
      status: "CONNECTED",
      message: "FlowProof can read Flow definitions as you."
    });
    const element = render();

    element.shadowRoot
      .querySelector("lightning-button.test-connection")
      .click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".connection-headline").textContent
    ).toBe("Connected");
    expect(element.shadowRoot.querySelector("lightning-icon").iconName).toBe(
      "utility:success"
    );
  });

  it("explains how to authorize when the connection is refused", async () => {
    testConnection.mockResolvedValue({
      connected: false,
      status: "NOT_AUTHORIZED",
      message:
        "Authorize FlowProof: Settings > External Credentials > FlowProof Org EC > Allow Access."
    });
    const element = render();

    element.shadowRoot
      .querySelector("lightning-button.test-connection")
      .click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".connection-headline").textContent
    ).toBe("Not authorized");
    expect(
      element.shadowRoot.querySelector(".connection-message").textContent
    ).toContain("Allow Access");
  });

  it("shows the error when the check itself fails", async () => {
    testConnection.mockRejectedValue({
      body: { message: "FlowProof ran into an unexpected error." }
    });
    const element = render();

    element.shadowRoot
      .querySelector("lightning-button.test-connection")
      .click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".connection-error").textContent
    ).toContain("unexpected error");
  });
});
