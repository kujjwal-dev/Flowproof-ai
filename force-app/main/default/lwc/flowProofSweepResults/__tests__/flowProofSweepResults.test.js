import { createElement } from "lwc";
import FlowProofSweepResults from "c/flowProofSweepResults";
import runInvestigation from "@salesforce/apex/FlowProofInvestigationController.runInvestigation";
import simulateAllFlows from "@salesforce/apex/FlowProofInvestigationController.simulateAllFlows";

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.runInvestigation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.simulateAllFlows",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const SWEEP = {
  objectApiName: "Opportunity",
  recordId: "006000000000001AAA",
  recordName: "Acme Corporation - Expansion",
  flowCount: 3,
  skippedFlowLabels: ["Legacy Flow"],
  whatIfFields: [
    {
      apiName: "Region__c",
      label: "Region",
      inputType: "picklist",
      value: null,
      options: [{ label: "North America", value: "North America" }]
    },
    { apiName: "Amount", label: "Amount", inputType: "number", value: "25000" },
    {
      apiName: "IsPrivate",
      label: "Private",
      inputType: "checkbox",
      value: "false"
    }
  ],
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

  it("re-checks the Flows with simulated values, sending only changes", async () => {
    simulateAllFlows.mockResolvedValue({
      ...SWEEP,
      simulated: true,
      simulatedChanges: ["Region__c: (blank) → North America"],
      rows: [
        { ...SWEEP.rows[0], overallCode: "SATISFIED", unmatchedConditions: [] }
      ]
    });
    const element = render();

    element.shadowRoot.querySelector("lightning-button.what-if-toggle").click();
    await flushPromises();
    const region = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="Region__c"]'
    );
    expect(region.options[0].label).toBe("(blank)");
    region.dispatchEvent(
      new CustomEvent("change", { detail: { value: "North America" } })
    );
    element.shadowRoot
      .querySelector('lightning-input[data-field="IsPrivate"]')
      .dispatchEvent(new CustomEvent("change", { detail: { checked: true } }));
    element.shadowRoot
      .querySelector("lightning-button.simulate-button")
      .click();
    await flushPromises();

    expect(simulateAllFlows).toHaveBeenCalledWith({
      objectApiName: "Opportunity",
      recordId: "006000000000001AAA",
      values: { Region__c: "North America", IsPrivate: "true" }
    });
    expect(
      element.shadowRoot.querySelector(".simulated-notice").textContent
    ).toContain("Region__c: (blank) → North America");
    expect(
      element.shadowRoot.querySelector('lightning-badge[data-id="overall"]')
        .label
    ).toBe("Conditions met");
    expect(element.shadowRoot.querySelector(".investigate-row")).toBeNull();

    element.shadowRoot.querySelector("lightning-button.show-current").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".simulated-notice")).toBeNull();
    expect(element.shadowRoot.querySelector(".investigate-row")).not.toBeNull();
  });

  it("asks for a change before simulating", async () => {
    const element = render();
    element.shadowRoot.querySelector("lightning-button.what-if-toggle").click();
    await flushPromises();

    element.shadowRoot
      .querySelector("lightning-button.simulate-button")
      .click();
    await flushPromises();

    expect(simulateAllFlows).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector(".what-if-error").textContent
    ).toContain("Change at least one value");
  });

  it("shows the server message when a simulated value is invalid", async () => {
    simulateAllFlows.mockRejectedValue({
      body: { message: '"lots" is not a valid value for Amount.' }
    });
    const element = render();
    element.shadowRoot.querySelector("lightning-button.what-if-toggle").click();
    await flushPromises();
    element.shadowRoot
      .querySelector('lightning-input[data-field="Amount"]')
      .dispatchEvent(new CustomEvent("change", { detail: { value: "lots" } }));

    element.shadowRoot
      .querySelector("lightning-button.simulate-button")
      .click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".what-if-error").textContent
    ).toContain("not a valid value");
  });
});
