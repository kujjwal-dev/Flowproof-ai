import { createElement } from "lwc";
import FlowProofAiExplanation from "c/flowProofAiExplanation";
import requestAiExplanation from "@salesforce/apex/FlowProofInvestigationController.requestAiExplanation";

jest.mock(
  "@salesforce/apex/FlowProofInvestigationController.requestAiExplanation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const INVESTIGATION_ID = "a00000000000001AAA";
const EXPLANATION = {
  summary: "Region is blank, so the conditions are not met.",
  keyPoints: [
    {
      text: "Region must be North America.",
      basedOn: ["CONDITIONS_NOT_MET", "C3"]
    }
  ],
  nextSteps: ["Set Region if that is correct."],
  droppedPointCount: 1,
  model: "gemini-3.8-flash"
};

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render(props = {}) {
  const element = createElement("c-flow-proof-ai-explanation", {
    is: FlowProofAiExplanation
  });
  element.investigationId = INVESTIGATION_ID;
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe("c-flow-proof-ai-explanation", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders nothing until there is an explanation", () => {
    const element = render();
    expect(element.shadowRoot.querySelector(".ai-explanation")).toBeNull();
  });

  it("shows a stored explanation in plain words only", async () => {
    const element = render({ explanation: EXPLANATION });
    await flushPromises();

    const section = element.shadowRoot.querySelector(".ai-explanation");
    expect(section.querySelector(".ai-summary").textContent).toBe(
      EXPLANATION.summary
    );
    expect(section.querySelector(".ai-point").textContent).toBe(
      "Region must be North America."
    );
    expect(section.textContent).not.toContain("gemini-3.8-flash");
    expect(section.textContent).not.toContain("CONDITIONS_NOT_MET");
    expect(section.querySelector(".ai-disclaimer").textContent).toContain(
      "AI-generated"
    );
  });

  it("generates an explanation when asked", async () => {
    requestAiExplanation.mockResolvedValue(EXPLANATION);
    const element = render();

    await element.generate(false);
    await flushPromises();

    expect(requestAiExplanation).toHaveBeenCalledWith({
      investigationId: INVESTIGATION_ID,
      regenerate: false
    });
    expect(element.shadowRoot.querySelector(".ai-summary").textContent).toBe(
      EXPLANATION.summary
    );
    expect(
      element.shadowRoot.querySelector("lightning-button.retry-button").label
    ).toBe("Regenerate");
  });

  it("regenerates a stored explanation", async () => {
    requestAiExplanation.mockResolvedValue({ ...EXPLANATION, summary: "New" });
    const element = render({ explanation: EXPLANATION });
    await flushPromises();

    element.shadowRoot.querySelector("lightning-button.retry-button").click();
    await flushPromises();

    expect(requestAiExplanation).toHaveBeenCalledWith({
      investigationId: INVESTIGATION_ID,
      regenerate: true
    });
    expect(element.shadowRoot.querySelector(".ai-summary").textContent).toBe(
      "New"
    );
  });

  it("shows the server message and lets the user try again", async () => {
    requestAiExplanation.mockRejectedValue({
      body: { message: "Gemini rejected the API key." }
    });
    const element = render();

    await element.generate(false);
    await flushPromises();

    expect(element.shadowRoot.querySelector(".ai-error").textContent).toContain(
      "rejected the API key"
    );
    expect(
      element.shadowRoot.querySelector("lightning-button.retry-button").label
    ).toBe("Try again");
  });
});
