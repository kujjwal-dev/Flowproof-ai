/**
 * One diagnostic finding: what FlowProof concluded, how strong the evidence is, and what to do next.
 * Findings sort by severity (high first), then category (confirmed first), then the order rules ran.
 *
 * @example
 * FlowProofFinding finding = new FlowProofFinding('NO_ACTIVE_VERSION',
 *     FlowProofFinding.Category.CONFIRMED, FlowProofFinding.Severity.HIGH)
 *     .describe('The Flow has no active version', 'It cannot run.', 'Activate it in Flow Builder.');
 */
public with sharing class FlowProofFinding implements Comparable {
    /** Strength of the evidence behind a finding. */
    public enum Category {
        /** Directly shown by metadata or data. */
        CONFIRMED,
        /** Consistent with the evidence, not proven (for example, based on current values). */
        SUPPORTED_HYPOTHESIS,
        /** The data needed to decide is not available. */
        INSUFFICIENT_EVIDENCE,
        /** The construct is outside what FlowProof can evaluate. */
        UNSUPPORTED
    }

    /** How much the finding matters for the investigation. */
    public enum Severity {
        HIGH,
        MEDIUM,
        LOW,
        INFO
    }

    /** Stable rule identifier, e.g. CONDITIONS_NOT_MET. */
    @AuraEnabled
    public String ruleCode { get; set; }
    // Apex enums arrive empty in Lightning components, so each enum has a String code that
    // Lightning reads. The enum setters keep the codes in sync (including on JSON deserialization).

    /** Strength of the evidence. Lightning components read categoryCode instead. */
    public Category category {
        get;
        set {
            category = value;
            categoryCode = value?.name();
        }
    }
    /** Category name for Lightning components, e.g. SUPPORTED_HYPOTHESIS. */
    @AuraEnabled
    public String categoryCode { get; set; }
    /** How much it matters. Lightning components read severityCode instead. */
    public Severity severity {
        get;
        set {
            severity = value;
            severityCode = value?.name();
        }
    }
    /** Severity name for Lightning components, e.g. HIGH. */
    @AuraEnabled
    public String severityCode { get; set; }
    /** One-line summary. */
    @AuraEnabled
    public String title { get; set; }
    /** Explanation, including the evidence used. */
    @AuraEnabled
    public String detail { get; set; }
    /** Recommended next step. */
    @AuraEnabled
    public String recommendation { get; set; }
    /** Position in which the rule produced the finding; breaks sorting ties. */
    @AuraEnabled
    public Integer sortOrder { get; set; }

    /**
     * No-arg constructor for deserialization.
     */
    public FlowProofFinding() {
        this.sortOrder = 0;
    }

    /**
     * @param ruleCode stable rule identifier
     * @param category strength of the evidence
     * @param severity how much it matters
     */
    public FlowProofFinding(String ruleCode, Category category, Severity severity) {
        this();
        this.ruleCode = ruleCode;
        this.category = category;
        this.severity = severity;
    }

    /**
     * Sets the user-facing text.
     * @param title one-line summary
     * @param detail explanation, including the evidence used
     * @param recommendation recommended next step
     * @return this finding, for chaining
     */
    public FlowProofFinding describe(String title, String detail, String recommendation) {
        this.title = title;
        this.detail = detail;
        this.recommendation = recommendation;
        return this;
    }

    /**
     * Orders by severity, then category, then rule order.
     * @param other another FlowProofFinding
     * @return negative, zero or positive
     */
    public Integer compareTo(Object other) {
        FlowProofFinding that = (FlowProofFinding) other;
        if (this.severity != that.severity) {
            return this.severity.ordinal() - that.severity.ordinal();
        }
        if (this.category != that.category) {
            return this.category.ordinal() - that.category.ordinal();
        }
        return this.sortOrder - that.sortOrder;
    }
}
