import { createElement } from "lwc";
import FlowProofHistory from "c/flowProofHistory";
import getRecentInvestigations from "@salesforce/apex/FlowProofInvestigationController.getRecentInvestigations";
import { refreshApex } from "@salesforce/apex";

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getRecentInvestigations",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const ROWS = [
  {
    investigationId: "a00000000000001AAA",
    name: "INV-0002",
    flowLabel: "Opportunity Onboarding",
    objectApiName: "Opportunity",
    overallResult: "NOT_SATISFIED",
    topFinding: "The record does not meet the Flow's entry conditions",
    findingCount: 3,
    createdDate: "2026-10-15T10:00:00.000Z"
  }
];

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render() {
  const element = createElement("c-flow-proof-history", {
    is: FlowProofHistory
  });
  document.body.appendChild(element);
  return element;
}

describe("c-flow-proof-history", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a spinner until investigations load", () => {
    const element = render();
    expect(
      element.shadowRoot.querySelector("lightning-spinner")
    ).not.toBeNull();
  });

  it("lists investigations with readable results", async () => {
    const element = render();
    getRecentInvestigations.emit(ROWS);
    await flushPromises();

    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data.length).toBe(1);
    expect(table.data[0].overallLabel).toBe("Conditions not met");
  });

  it("shows an empty state when there are no investigations", async () => {
    const element = render();
    getRecentInvestigations.emit([]);
    await flushPromises();

    expect(element.shadowRoot.querySelector(".empty-state")).not.toBeNull();
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
  });

  it("shows the error when investigations cannot load", async () => {
    const element = render();
    getRecentInvestigations.error({ message: "No access to investigations." });
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".history-error").textContent
    ).toContain("No access");
  });

  it("asks to open an investigation when its row is clicked", async () => {
    const element = render();
    const handler = jest.fn();
    element.addEventListener("viewinvestigation", handler);
    getRecentInvestigations.emit(ROWS);
    await flushPromises();

    element.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "view" }, row: ROWS[0] }
      })
    );

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.investigationId).toBe(
      "a00000000000001AAA"
    );
  });

  it("reloads from the server on refresh", async () => {
    const element = render();
    getRecentInvestigations.emit(ROWS);
    await flushPromises();

    await element.refresh();

    expect(refreshApex).toHaveBeenCalledTimes(1);
  });
});
