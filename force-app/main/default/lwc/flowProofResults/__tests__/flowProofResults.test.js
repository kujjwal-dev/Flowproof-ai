import { createElement } from "lwc";
import FlowProofResults from "c/flowProofResults";
import getSettings from "@salesforce/apex/FlowProofInvestigationController.getSettings";
import requestAiExplanation from "@salesforce/apex/FlowProofInvestigationController.requestAiExplanation";

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getSettings",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.requestAiExplanation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const mockNavigate = jest.fn();
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageReference) {
        mockNavigate(pageReference);
      }
    };
  NavigationMixin.Navigate = Navigate;
  NavigationMixin.GenerateUrl = Symbol("GenerateUrl");
  return { NavigationMixin };
});

const RESULT = {
  investigationName: "INV-0001",
  objectApiName: "Opportunity",
  recordId: "006000000000001AAA",
  recordName: "Acme Corporation - Expansion",
  expectedOutcome: "An onboarding Task should be created",
  investigatedAt: "2026-10-15T10:00:00.000Z",
  conditionsRead: true,
  triggerObject: "Opportunity",
  recordTriggerType: "CreateAndUpdate",
  runsOnlyWhenUpdatedToMeetConditions: true,
  flow: {
    apiName: "Opportunity_Onboarding",
    label: "Opportunity Onboarding",
    activeVersionId: "301000000000001AAA",
    triggerType: "RecordAfterSave"
  },
  evaluation: {
    overallCode: "NOT_SATISFIED",
    logicType: "AND",
    overallReason:
      "All conditions must match, and condition(s) 3 do not match the current values.",
    conditions: [
      {
        index: 1,
        field: "StageName",
        operator: "EqualTo",
        expectedDisplay: "Closed Won",
        actualDisplay: "Closed Won",
        outcomeCode: "MATCH",
        reason: "The field equals Closed Won."
      },
      {
        index: 2,
        field: "Amount",
        operator: "GreaterThan",
        expectedDisplay: "10000",
        actualDisplay: "25000",
        outcomeCode: "MATCH",
        reason: "ok"
      },
      {
        index: 3,
        field: "Region__c",
        operator: "EqualTo",
        expectedDisplay: "North America",
        actualDisplay: "(blank)",
        outcomeCode: "NO_MATCH",
        reason: "The field is blank."
      }
    ]
  },
  findings: [
    {
      ruleCode: "CONDITIONS_NOT_MET",
      categoryCode: "SUPPORTED_HYPOTHESIS",
      severityCode: "HIGH",
      title: "The record does not meet the Flow's entry conditions",
      detail: "Condition #3 fails.",
      recommendation: "Check the failing fields on the record."
    },
    {
      ruleCode: "EXECUTION_NOT_CONFIRMED",
      categoryCode: "INSUFFICIENT_EVIDENCE",
      severityCode: "INFO",
      title: "Whether the Flow actually ran is not confirmed",
      detail: "No per-record history.",
      recommendation: "Use a debug log."
    }
  ],
  healthChecked: true,
  healthFindings: [
    {
      ruleCode: "MISSING_FAULT_PATHS",
      categoryCode: "CONFIRMED",
      severityCode: "LOW",
      title: "Some elements have no fault path",
      detail: '"Create Task" (Create Records) has no fault path.',
      recommendation: "Add a fault path."
    }
  ]
};

function findingItems(element, listId) {
  return element.shadowRoot
    .querySelector(`c-flow-proof-finding-list[data-id="${listId}"]`)
    .shadowRoot.querySelectorAll("li.finding");
}

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render(result) {
  const element = createElement("c-flow-proof-results", {
    is: FlowProofResults
  });
  element.result = result;
  document.body.appendChild(element);
  return element;
}

describe("c-flow-proof-results", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders nothing without a result", () => {
    const element = render(undefined);
    expect(element.shadowRoot.querySelector("lightning-card")).toBeNull();
  });

  it("shows the investigation, Flow and overall result", () => {
    const element = render(RESULT);
    expect(element.shadowRoot.querySelector(".results-title").textContent).toBe(
      "INV-0001: Opportunity Onboarding"
    );
    expect(
      element.shadowRoot.querySelector('lightning-badge[data-id="overall"]')
        .label
    ).toBe("Conditions not met");
    expect(
      element.shadowRoot.querySelector(".expected-outcome").textContent
    ).toContain("onboarding Task");
  });

  it("shows the record name instead of its Id", () => {
    const element = render(RESULT);
    expect(
      element.shadowRoot.querySelector("lightning-card").textContent
    ).toContain("Opportunity: Acme Corporation - Expansion");
  });

  it("always states that execution is not confirmed", () => {
    const element = render(RESULT);
    expect(
      element.shadowRoot.querySelector(".execution-notice").textContent
    ).toContain("not confirmed");
  });

  it("lists findings with evidence category and next step", () => {
    const element = render(RESULT);
    const findings = findingItems(element, "findings");
    // "Not confirmed" is shown once, as the note under the header, not as a finding.
    expect(findings.length).toBe(1);
    expect(findings[0].querySelector(".finding-title").textContent).toContain(
      "does not meet"
    );
    expect(findings[0].querySelector("lightning-badge").label).toBe(
      "Supported hypothesis"
    );
    expect(
      findings[0].querySelector(".finding-next-step").textContent
    ).toContain("Check the failing fields");
    expect(findings[0].querySelector("lightning-icon").alternativeText).toBe(
      "High severity"
    );
  });

  it("lists Flow health suggestions apart from the findings", () => {
    const element = render(RESULT);
    const health = findingItems(element, "health");
    expect(health.length).toBe(1);
    expect(health[0].querySelector(".finding-title").textContent).toContain(
      "no fault path"
    );
    expect(health[0].querySelector(".finding-next-step").textContent).toContain(
      "Suggestion:"
    );
  });

  it("says when Flow health could not be checked", () => {
    const element = render({
      ...RESULT,
      healthChecked: false,
      healthFindings: []
    });
    const list = element.shadowRoot.querySelector(
      'c-flow-proof-finding-list[data-id="health"]'
    );
    expect(list.shadowRoot.querySelector(".empty-text").textContent).toContain(
      "not checked"
    );
  });

  it("offers an AI explanation when AI is on", async () => {
    requestAiExplanation.mockResolvedValue({ summary: "Region is blank." });
    const element = render({
      ...RESULT,
      investigationId: "a00000000000001AAA"
    });
    expect(element.shadowRoot.querySelector(".explain-button")).toBeNull();

    getSettings.emit({ aiEnabled: true });
    await flushPromises();
    const button = element.shadowRoot.querySelector(
      "lightning-button.explain-button"
    );
    expect(button.label).toBe("AI explanation");
    button.click();
    await flushPromises();

    expect(requestAiExplanation).toHaveBeenCalledWith({
      investigationId: "a00000000000001AAA",
      regenerate: false
    });
    expect(element.shadowRoot.querySelector(".explain-button")).toBeNull();
  });

  it("does not offer an AI explanation when one is stored", async () => {
    const element = render({
      ...RESULT,
      investigationId: "a00000000000001AAA",
      aiExplanation: { summary: "Stored." }
    });
    getSettings.emit({ aiEnabled: true });
    await flushPromises();

    expect(element.shadowRoot.querySelector(".explain-button")).toBeNull();
  });

  it("shows each condition with expected value, current value and result", () => {
    const element = render(RESULT);
    const rows = element.shadowRoot.querySelectorAll("tr.condition-row");
    expect(rows.length).toBe(3);
    const regionCells = rows[2].querySelectorAll("td");
    expect(regionCells[0].textContent).toBe("Region__c");
    expect(regionCells[1].textContent).toBe("Equals");
    expect(regionCells[3].textContent).toBe("(blank)");
    expect(rows[2].querySelector("lightning-badge").label).toBe("No match");
  });

  it("describes the Flow trigger settings", () => {
    const element = render(RESULT);
    const details =
      element.shadowRoot.querySelector(".flow-details").textContent;
    expect(details).toContain("After save: A record is created or updated");
    expect(details).toContain("Active");
  });

  it("explains when the conditions could not be read", () => {
    const element = render({
      ...RESULT,
      evaluation: null,
      conditionsRead: false
    });
    expect(
      element.shadowRoot.querySelector(".no-conditions").textContent
    ).toContain("could not be read");
    expect(
      element.shadowRoot.querySelector('lightning-badge[data-id="overall"]')
        .label
    ).toBe("Not evaluated");
  });

  it("opens the investigated record", () => {
    const element = render(RESULT);
    element.shadowRoot.querySelector("lightning-button.open-record").click();
    expect(mockNavigate).toHaveBeenCalledTimes(1);
    const pageReference = mockNavigate.mock.calls[0][0];
    expect(pageReference.type).toBe("standard__recordPage");
    expect(pageReference.attributes.recordId).toBe(RESULT.recordId);
  });
});
