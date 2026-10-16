import { createElement } from "lwc";
import FlowProofRecordCheck from "c/flowProofRecordCheck";
import checkAllFlows from "@salesforce/apex/FlowProofInvestigationController.checkAllFlows";

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.checkAllFlows",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getSettings",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const RECORD_ID = "006000000000001AAA";
const SWEEP = {
  objectApiName: "Opportunity",
  recordId: RECORD_ID,
  recordName: "Acme",
  flowCount: 0,
  rows: [],
  whatIfFields: []
};

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render(props = {}) {
  const element = createElement("c-flow-proof-record-check", {
    is: FlowProofRecordCheck
  });
  element.recordId = RECORD_ID;
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe("c-flow-proof-record-check", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("does not check anything until asked", () => {
    render();
    expect(checkAllFlows).not.toHaveBeenCalled();
  });

  it("checks the record's Flows and shows the list", async () => {
    checkAllFlows.mockResolvedValue(SWEEP);
    const element = render({ objectApiName: "Opportunity" });

    element.shadowRoot.querySelector("lightning-button.check-button").click();
    await flushPromises();

    expect(checkAllFlows).toHaveBeenCalledWith({
      objectApiName: "Opportunity",
      recordId: RECORD_ID
    });
    expect(
      element.shadowRoot.querySelector("c-flow-proof-sweep-results").sweep
        .recordName
    ).toBe("Acme");
  });

  it("lets Apex find the object when the action does not pass it", async () => {
    checkAllFlows.mockResolvedValue(SWEEP);
    const element = render();

    element.shadowRoot.querySelector("lightning-button.check-button").click();
    await flushPromises();

    expect(checkAllFlows).toHaveBeenCalledWith({
      objectApiName: null,
      recordId: RECORD_ID
    });
  });

  it("shows a full investigation opened from the list", async () => {
    checkAllFlows.mockResolvedValue(SWEEP);
    const element = render();
    element.shadowRoot.querySelector("lightning-button.check-button").click();
    await flushPromises();

    element.shadowRoot
      .querySelector("c-flow-proof-sweep-results")
      .dispatchEvent(
        new CustomEvent("investigationcomplete", {
          detail: { investigationName: "INV-0042", flow: { label: "X" } }
        })
      );
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".latest-result c-flow-proof-results")
        .result.investigationName
    ).toBe("INV-0042");
  });

  it("shows the server message when the check fails", async () => {
    checkAllFlows.mockRejectedValue({
      body: { message: "You do not have access to this record." }
    });
    const element = render();

    element.shadowRoot.querySelector("lightning-button.check-button").click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".check-error").textContent
    ).toContain("You do not have access");
  });
});
