import { createElement } from "lwc";
import FlowProofNewInvestigation from "c/flowProofNewInvestigation";
import getObjectOptions from "@salesforce/apex/FlowProofInvestigationController.getObjectOptions";
import getFlows from "@salesforce/apex/FlowProofInvestigationController.getFlows";
import runInvestigation from "@salesforce/apex/FlowProofInvestigationController.runInvestigation";

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getObjectOptions",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.getFlows",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.runInvestigation",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const OBJECTS = [
  { apiName: "Opportunity", label: "Opportunity", flowCount: 1 }
];
const FLOWS = [
  {
    apiName: "Opportunity_Onboarding",
    label: "Opportunity Onboarding",
    activeVersionId: "301000000000001AAA",
    triggerType: "RecordAfterSave"
  }
];
const RECORD_ID = "006000000000001AAA";

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render() {
  const element = createElement("c-flow-proof-new-investigation", {
    is: FlowProofNewInvestigation
  });
  document.body.appendChild(element);
  return element;
}

function change(element, selector, detail) {
  element.shadowRoot
    .querySelector(selector)
    .dispatchEvent(new CustomEvent("change", { detail }));
}

async function fillForm(element) {
  getObjectOptions.emit(OBJECTS);
  await flushPromises();
  change(element, 'lightning-combobox[data-id="object"]', {
    value: "Opportunity"
  });
  await flushPromises();
  getFlows.emit(FLOWS);
  await flushPromises();
  change(element, "lightning-record-picker", { recordId: RECORD_ID });
  change(element, 'lightning-combobox[data-id="flow"]', {
    value: "Opportunity_Onboarding"
  });
  await flushPromises();
}

describe("c-flow-proof-new-investigation", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a spinner until the objects load", () => {
    const element = render();
    expect(
      element.shadowRoot.querySelector("lightning-spinner")
    ).not.toBeNull();
  });

  it("lists objects with their Flow counts", async () => {
    const element = render();
    getObjectOptions.emit(OBJECTS);
    await flushPromises();

    const objectPicker = element.shadowRoot.querySelector(
      'lightning-combobox[data-id="object"]'
    );
    expect(objectPicker.options).toEqual([
      { label: "Opportunity (1 Flow)", value: "Opportunity" }
    ]);
  });

  it("explains when no object has record-triggered Flows", async () => {
    const element = render();
    getObjectOptions.emit([]);
    await flushPromises();

    expect(element.shadowRoot.querySelector(".no-objects")).not.toBeNull();
    expect(element.shadowRoot.querySelector("lightning-combobox")).toBeNull();
  });

  it("shows the error when objects cannot be loaded", async () => {
    const element = render();
    getObjectOptions.error({
      message: "You do not have permission to view Flow definitions."
    });
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".objects-error").textContent
    ).toContain("You do not have permission");
  });

  it("lists the chosen object's Flows with their state", async () => {
    const element = render();
    getObjectOptions.emit(OBJECTS);
    await flushPromises();
    change(element, 'lightning-combobox[data-id="object"]', {
      value: "Opportunity"
    });
    await flushPromises();
    getFlows.emit(FLOWS);
    await flushPromises();

    const flowPicker = element.shadowRoot.querySelector(
      'lightning-combobox[data-id="flow"]'
    );
    expect(flowPicker.options[0].label).toBe(
      "Opportunity Onboarding (Active, after save)"
    );
    expect(flowPicker.disabled).toBe(false);
  });

  it("keeps Investigate disabled until object, record and Flow are chosen", async () => {
    const element = render();
    getObjectOptions.emit(OBJECTS);
    await flushPromises();
    const button = element.shadowRoot.querySelector(
      "lightning-button.investigate-button"
    );
    expect(button.disabled).toBe(true);

    await fillForm(element);
    expect(
      element.shadowRoot.querySelector("lightning-button.investigate-button")
        .disabled
    ).toBe(false);
  });

  it("runs the investigation and reports the saved result", async () => {
    runInvestigation.mockResolvedValue({ investigationName: "INV-0001" });
    const element = render();
    const handler = jest.fn();
    element.addEventListener("investigationcomplete", handler);
    await fillForm(element);

    element.shadowRoot
      .querySelector("lightning-button.investigate-button")
      .click();
    await flushPromises();

    expect(runInvestigation).toHaveBeenCalledWith({
      objectApiName: "Opportunity",
      recordId: RECORD_ID,
      flowApiName: "Opportunity_Onboarding",
      expectedOutcome: null
    });
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.investigationName).toBe("INV-0001");
  });

  it("shows the server message when the investigation fails", async () => {
    runInvestigation.mockRejectedValue({
      body: {
        message: "The record was not found, or you do not have access to it."
      }
    });
    const element = render();
    await fillForm(element);

    element.shadowRoot
      .querySelector("lightning-button.investigate-button")
      .click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".run-error").textContent
    ).toContain("The record was not found");
  });

  it("clears the record and Flow when the object changes", async () => {
    const element = render();
    await fillForm(element);

    change(element, 'lightning-combobox[data-id="object"]', {
      value: "Account"
    });
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("lightning-button.investigate-button")
        .disabled
    ).toBe(true);
  });
});
