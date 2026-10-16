import { createElement } from "lwc";
import FlowProofSweepResults from "c/flowProofSweepResults";
import runInvestigation from "@salesforce/apex/FlowProofInvestigationController.runInvestigation";

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.runInvestigation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const SWEEP = {
  objectApiName: "Opportunity",
  recordId: "006000000000001AAA",
  recordName: "Acme Corporation - Expansion",
  flowCount: 3,
  skippedFlowLabels: ["Legacy Flow"],
  rows: [
    {
      flowApiName: "Opportunity_Onboarding",
      flowLabel: "Opportunity Onboarding",
      isActive: true,
      triggerType: "RecordAfterSave",
      overallCode: "NOT_SATISFIED",
      unmatchedConditions: [
        {
          index: 3,
          field: "Region__c",
          operator: "EqualTo",
          expectedDisplay: "North America",
          actualDisplay: "(blank)",
          outcomeCode: "NO_MATCH"
        }
      ],
      topFinding: { title: "The record does not meet the entry conditions" },
      healthChecked: true,
      healthCount: 2,
      topHealthFinding: { title: "Some elements have no fault path" }
    },
    {
      flowApiName: "Archived_Flow",
      flowLabel: "Archived Flow",
      isActive: false,
      triggerType: "RecordAfterSave",
      overallCode: "SATISFIED",
      unmatchedConditions: [],
      topFinding: { title: "The Flow has no active version" },
      healthChecked: false,
      healthCount: 0
    }
  ]
};

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render(sweep = SWEEP) {
  const element = createElement("c-flow-proof-sweep-results", {
    is: FlowProofSweepResults
  });
  element.sweep = sweep;
  document.body.appendChild(element);
  return element;
}

describe("c-flow-proof-sweep-results", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("summarizes the check and names the record", () => {
    const element = render();
    expect(element.shadowRoot.querySelector(".sweep-title").textContent).toBe(
      "All Flows on Opportunity: Acme Corporation - Expansion"
    );
    expect(
      element.shadowRoot.querySelector(".sweep-summary").textContent
    ).toContain("Checked 2 of 3");
    expect(
      element.shadowRoot.querySelector(".execution-notice").textContent
    ).toContain("not proof");
    expect(
      element.shadowRoot.querySelector(".skipped-notice").textContent
    ).toContain("Legacy Flow");
  });

  it("shows each Flow's result, failing condition and health", () => {
    const element = render();
    const rows = element.shadowRoot.querySelectorAll("tr.sweep-row");
    expect(rows.length).toBe(2);
    expect(
      rows[0].querySelector('lightning-badge[data-id="overall"]').label
    ).toBe("Conditions not met");
    expect(rows[0].querySelector(".unmatched-condition").textContent).toContain(
      "Region__c equals North America: no match"
    );
    expect(rows[0].querySelector(".health-cell").textContent).toContain(
      "2 suggestions"
    );
    expect(rows[1].querySelector("lightning-badge").label).toBe("Inactive");
    expect(rows[1].querySelector(".health-cell").textContent).toContain(
      "Not checked"
    );
  });

  it("runs a full investigation for a Flow and reports it", async () => {
    runInvestigation.mockResolvedValue({ investigationName: "INV-0010" });
    const element = render();
    const handler = jest.fn();
    element.addEventListener("investigationcomplete", handler);

    element.shadowRoot
      .querySelector("lightning-button.investigate-row")
      .click();
    await flushPromises();

    expect(runInvestigation).toHaveBeenCalledWith({
      objectApiName: "Opportunity",
      recordId: "006000000000001AAA",
      flowApiName: "Opportunity_Onboarding",
      expectedOutcome: null
    });
    expect(handler.mock.calls[0][0].detail.investigationName).toBe("INV-0010");
  });

  it("shows the server message when the investigation fails", async () => {
    runInvestigation.mockRejectedValue({
      body: { message: "You do not have access to this record." }
    });
    const element = render();

    element.shadowRoot
      .querySelector("lightning-button.investigate-row")
      .click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".run-error").textContent
    ).toContain("You do not have access");
  });

  it("explains when the object has no Flows", () => {
    const element = render({ ...SWEEP, rows: [], skippedFlowLabels: [] });
    expect(element.shadowRoot.querySelector(".no-flows")).not.toBeNull();
  });
});
