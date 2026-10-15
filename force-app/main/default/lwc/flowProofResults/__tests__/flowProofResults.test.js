import { createElement } from "lwc";
import FlowProofResults from "c/flowProofResults";

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
  ]
};

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
    const findings = element.shadowRoot.querySelectorAll("li.finding");
    expect(findings.length).toBe(2);
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
