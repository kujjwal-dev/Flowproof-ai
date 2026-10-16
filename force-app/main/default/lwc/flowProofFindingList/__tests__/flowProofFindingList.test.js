import { createElement } from "lwc";
import FlowProofFindingList from "c/flowProofFindingList";

const FINDING = {
  ruleCode: "DATA_OPERATION_IN_LOOP",
  categoryCode: "CONFIRMED",
  severityCode: "HIGH",
  title: "Records are read or saved inside a loop",
  detail: 'Found inside loop "Loop Contacts" (Loop).',
  recommendation: "Save the collection once after the loop."
};

function render(props) {
  const element = createElement("c-flow-proof-finding-list", {
    is: FlowProofFindingList
  });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe("c-flow-proof-finding-list", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows each finding with severity, evidence category and next step", () => {
    const element = render({ findings: [FINDING] });
    const item = element.shadowRoot.querySelector("li.finding");
    expect(item.querySelector(".finding-title").textContent).toContain(
      "inside a loop"
    );
    expect(item.querySelector("lightning-badge").label).toBe(
      "Confirmed by evidence"
    );
    expect(item.querySelector("lightning-icon").alternativeText).toBe(
      "High severity"
    );
    expect(item.querySelector(".finding-next-step").textContent).toContain(
      "Next step:"
    );
  });

  it("uses a custom label before recommendations", () => {
    const element = render({
      findings: [FINDING],
      nextStepLabel: "Suggestion:"
    });
    expect(
      element.shadowRoot.querySelector(".finding-next-step").textContent
    ).toContain("Suggestion:");
  });

  it("shows the empty text when there are no findings", () => {
    const element = render({ findings: [], emptyText: "Nothing to fix." });
    expect(element.shadowRoot.querySelector("li.finding")).toBeNull();
    expect(element.shadowRoot.querySelector(".empty-text").textContent).toBe(
      "Nothing to fix."
    );
  });
});
