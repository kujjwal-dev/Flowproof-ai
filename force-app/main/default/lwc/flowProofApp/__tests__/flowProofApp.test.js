import { createElement } from "lwc";
import FlowProofApp from "c/flowProofApp";
import getInvestigation from "@salesforce/apex/FlowProofInvestigationController.getInvestigation";

// jest.mock factories must be inline functions (they are hoisted above the imports).
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getObjectOptions",
  () => ({
    default: require("@salesforce/sfdx-lwc-jest").createApexTestWireAdapter(
      jest.fn()
    )
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getFlows",
  () => ({
    default: require("@salesforce/sfdx-lwc-jest").createApexTestWireAdapter(
      jest.fn()
    )
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getRecentInvestigations",
  () => ({
    default: require("@salesforce/sfdx-lwc-jest").createApexTestWireAdapter(
      jest.fn()
    )
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getSettings",
  () => ({
    default: require("@salesforce/sfdx-lwc-jest").createApexTestWireAdapter(
      jest.fn()
    )
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.runInvestigation",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getInvestigation",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.testConnection",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const RESULT = {
  investigationId: "a00000000000001AAA",
  investigationName: "INV-0001",
  objectApiName: "Opportunity",
  recordId: "006000000000001AAA",
  flow: {
    label: "Opportunity Onboarding",
    activeVersionId: "301000000000001AAA",
    triggerType: "RecordAfterSave"
  },
  findings: []
};

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render() {
  const element = createElement("c-flow-proof-app", { is: FlowProofApp });
  document.body.appendChild(element);
  return element;
}

describe("c-flow-proof-app", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("offers New investigation, History and Settings tabs", () => {
    const element = render();
    const labels = Array.from(
      element.shadowRoot.querySelectorAll("lightning-tab")
    ).map((tab) => tab.label);
    expect(labels).toEqual(["New investigation", "History", "Settings"]);
  });

  it("shows the branded banner with the logo and highlights", () => {
    const element = render();
    const logo = element.shadowRoot.querySelector("img.hero-logo");
    expect(logo.getAttribute("src")).toContain("FlowProofLogo");
    expect(element.shadowRoot.querySelector(".hero-title").textContent).toBe(
      "Why didn't my Flow run?"
    );
    expect(element.shadowRoot.querySelectorAll("li.hero-chip").length).toBe(4);
  });

  it("shows a check of all Flows and keeps it while a Flow is investigated", async () => {
    const element = render();
    element.shadowRoot
      .querySelector("c-flow-proof-new-investigation")
      .dispatchEvent(
        new CustomEvent("sweepcomplete", {
          detail: { objectApiName: "Opportunity", flowCount: 0, rows: [] }
        })
      );
    await flushPromises();
    const sweep = element.shadowRoot.querySelector(
      ".latest-sweep c-flow-proof-sweep-results"
    );
    expect(sweep.sweep.objectApiName).toBe("Opportunity");

    sweep.dispatchEvent(
      new CustomEvent("investigationcomplete", { detail: RESULT })
    );
    await flushPromises();

    expect(element.shadowRoot.querySelector(".latest-sweep")).not.toBeNull();
    expect(
      element.shadowRoot.querySelector(".latest-result c-flow-proof-results")
        .result.investigationName
    ).toBe("INV-0001");
  });

  it("shows the result after an investigation completes", async () => {
    const element = render();
    expect(element.shadowRoot.querySelector(".latest-result")).toBeNull();

    element.shadowRoot
      .querySelector("c-flow-proof-new-investigation")
      .dispatchEvent(
        new CustomEvent("investigationcomplete", { detail: RESULT })
      );
    await flushPromises();

    const results = element.shadowRoot.querySelector(
      ".latest-result c-flow-proof-results"
    );
    expect(results.result.investigationName).toBe("INV-0001");
  });

  it("opens a past investigation from History and goes back", async () => {
    getInvestigation.mockResolvedValue(RESULT);
    const element = render();

    element.shadowRoot.querySelector("c-flow-proof-history").dispatchEvent(
      new CustomEvent("viewinvestigation", {
        detail: { investigationId: RESULT.investigationId }
      })
    );
    await flushPromises();

    expect(getInvestigation).toHaveBeenCalledWith({
      investigationId: RESULT.investigationId
    });
    expect(
      element.shadowRoot.querySelector("lightning-button.back-button")
    ).not.toBeNull();

    element.shadowRoot.querySelector("lightning-button.back-button").click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("c-flow-proof-history")
    ).not.toBeNull();
  });

  it("shows the error when a past investigation cannot be opened", async () => {
    getInvestigation.mockRejectedValue({
      body: {
        message:
          "The investigation was not found, or you do not have access to it."
      }
    });
    const element = render();

    element.shadowRoot.querySelector("c-flow-proof-history").dispatchEvent(
      new CustomEvent("viewinvestigation", {
        detail: { investigationId: RESULT.investigationId }
      })
    );
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".view-error").textContent
    ).toContain("was not found");
  });
});
