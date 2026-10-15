import {
  categoryInfo,
  errorMessage,
  flowOptionLabel,
  operatorLabel,
  outcomeInfo,
  overallInfo,
  recordTriggerTypeLabel,
  severityInfo,
  triggerTypeLabel
} from "c/flowProofFormat";

describe("c/flowProofFormat", () => {
  it("labels every evidence category", () => {
    expect(categoryInfo("CONFIRMED").label).toBe("Confirmed by evidence");
    expect(categoryInfo("SUPPORTED_HYPOTHESIS").label).toBe(
      "Supported hypothesis"
    );
    expect(categoryInfo("INSUFFICIENT_EVIDENCE").label).toBe(
      "Insufficient evidence"
    );
    expect(categoryInfo("UNSUPPORTED").label).toBe("Unsupported analysis");
  });

  it("falls back for unknown values instead of failing", () => {
    expect(categoryInfo("SOMETHING_NEW").label).toBe("Unknown");
    expect(outcomeInfo(undefined).label).toBe("Unknown");
    expect(severityInfo("SOMETHING_NEW").label).toBe("Info");
    expect(operatorLabel("Contains")).toBe("Contains");
  });

  it("treats a missing overall result as not evaluated", () => {
    expect(overallInfo(undefined).label).toBe("Not evaluated");
    expect(overallInfo("NOT_SATISFIED").label).toBe("Conditions not met");
  });

  it("uses an error icon for high severity", () => {
    expect(severityInfo("HIGH")).toEqual(
      expect.objectContaining({
        iconName: "utility:error",
        iconVariant: "error"
      })
    );
  });

  it("describes operators and triggers in words", () => {
    expect(operatorLabel("GreaterThan")).toBe("Greater than");
    expect(operatorLabel("isnull")).toBe("Is null");
    expect(triggerTypeLabel("RecordAfterSave")).toBe("After save");
    expect(triggerTypeLabel(undefined)).toBe("Not triggered by records");
    expect(recordTriggerTypeLabel("CreateAndUpdate")).toBe(
      "A record is created or updated"
    );
  });

  it("formats Flow options with activation and trigger", () => {
    expect(
      flowOptionLabel({
        label: "Opportunity Onboarding",
        activeVersionId: "301x",
        triggerType: "RecordAfterSave"
      })
    ).toBe("Opportunity Onboarding (Active, after save)");
    expect(
      flowOptionLabel({ label: "Draft Flow", activeVersionId: null })
    ).toBe("Draft Flow (Inactive)");
  });

  it("reads Apex, LDS and JavaScript errors", () => {
    expect(
      errorMessage({ body: { message: "No Flow named X was found." } })
    ).toBe("No Flow named X was found.");
    expect(
      errorMessage({ body: [{ message: "First." }, { message: "Second." }] })
    ).toBe("First. Second.");
    expect(errorMessage(new Error("Network down"))).toBe("Network down");
    expect(errorMessage({})).toBe("Something went wrong.");
    expect(errorMessage(null)).toBe("");
  });
});
