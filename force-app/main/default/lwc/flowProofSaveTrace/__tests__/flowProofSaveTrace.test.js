import { createElement } from "lwc";
import FlowProofSaveTrace from "c/flowProofSaveTrace";
import startSaveTrace from "@salesforce/apex/FlowProofInvestigationController.startSaveTrace";
import readSaveTrace from "@salesforce/apex/FlowProofInvestigationController.readSaveTrace";
import stopSaveTrace from "@salesforce/apex/FlowProofInvestigationController.stopSaveTrace";

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.startSaveTrace",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.readSaveTrace",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.stopSaveTrace",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const RECORD_ID = "006000000000001AAA";
const SESSION = { recordId: RECORD_ID, traceFlagId: "7tf000000000001AAA" };
const TRACE = {
  logFound: true,
  matchedBy: "RECORD_ID",
  savedAt: "2026-10-18T10:17:05.000Z",
  source: "Lightning page",
  loggingStopped: true,
  ran: [
    {
      label: "Opportunity Onboarding",
      statusCode: "FINISHED",
      elements: ['"Create_Onboarding_Task" (Create Records)'],
      outcomes: [],
      errors: []
    },
    {
      label: "Account Sync",
      statusCode: "FAILED",
      elements: [],
      outcomes: [],
      errors: ["Required fields are missing: [Name]"]
    }
  ],
  notStarted: ["Discount Approval"],
  validationFailures: []
};

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render() {
  const element = createElement("c-flow-proof-save-trace", {
    is: FlowProofSaveTrace
  });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  return element;
}

async function startRecording(element) {
  startSaveTrace.mockResolvedValue(SESSION);
  element.shadowRoot.querySelector("lightning-button.start-button").click();
  await flushPromises();
}

describe("c-flow-proof-save-trace", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("starts recording and explains the next steps", async () => {
    const element = render();
    await startRecording(element);

    expect(startSaveTrace).toHaveBeenCalledWith({ recordId: RECORD_ID });
    expect(element.shadowRoot.querySelector(".steps").textContent).toContain(
      "save it"
    );
    expect(element.shadowRoot.querySelector(".read-button")).not.toBeNull();
  });

  it("shows which Flows ran, failed and did not start", async () => {
    readSaveTrace.mockResolvedValue(TRACE);
    const element = render();
    await startRecording(element);

    element.shadowRoot.querySelector("lightning-button.read-button").click();
    await flushPromises();

    expect(readSaveTrace).toHaveBeenCalledWith({ session: SESSION });
    const runs = element.shadowRoot.querySelectorAll("li.run");
    expect(runs.length).toBe(2);
    expect(runs[0].querySelector("lightning-badge").label).toBe("Ran");
    expect(runs[0].querySelector(".elements").textContent).toContain(
      "Create_Onboarding_Task"
    );
    expect(runs[1].querySelector("lightning-badge").label).toBe("Failed");
    expect(runs[1].querySelector(".run-error").textContent).toContain(
      "Required fields"
    );
    expect(
      element.shadowRoot.querySelector(".not-started").textContent
    ).toContain("Discount Approval");
    expect(element.shadowRoot.querySelector(".note").textContent).toContain(
      "Logging is off again"
    );
  });

  it("keeps recording when no save was logged yet", async () => {
    readSaveTrace.mockResolvedValue({
      logFound: false,
      message: "No save was logged yet."
    });
    const element = render();
    await startRecording(element);

    element.shadowRoot.querySelector("lightning-button.read-button").click();
    await flushPromises();

    expect(element.shadowRoot.querySelector(".not-found").textContent).toBe(
      "No save was logged yet."
    );
    expect(element.shadowRoot.querySelector(".read-button")).not.toBeNull();
  });

  it("switches logging off on cancel", async () => {
    stopSaveTrace.mockResolvedValue(undefined);
    const element = render();
    await startRecording(element);

    element.shadowRoot.querySelector("lightning-button.cancel-button").click();
    await flushPromises();

    expect(stopSaveTrace).toHaveBeenCalledWith({ session: SESSION });
    expect(element.shadowRoot.querySelector(".start-button")).not.toBeNull();
  });

  it("shows the server message when logging cannot start", async () => {
    startSaveTrace.mockRejectedValue({
      body: { message: "You need permission to manage debug logs." }
    });
    const element = render();

    element.shadowRoot.querySelector("lightning-button.start-button").click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".trace-error").textContent
    ).toContain("permission to manage debug logs");
    expect(element.shadowRoot.querySelector(".start-button")).not.toBeNull();
  });
});
