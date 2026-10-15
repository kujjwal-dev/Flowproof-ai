/**
 * Outcome of evaluating a Flow's entry conditions against a record snapshot.
 * Purely deterministic: produced without AI and without historical data, so an
 * outcome describes the record's CURRENT values only.
 */
public with sharing class FlowProofEvaluationResult {
    /** Result of a single condition. */
    public enum ConditionOutcome {
        MATCH,
        NO_MATCH,
        /** Evaluable, but platform semantics for this case are unverified. */
        UNCERTAIN,
        /** Construct outside the evaluator's supported scope. */
        UNSUPPORTED,
        /** Running user cannot read the field. */
        INACCESSIBLE,
        /** The object has no such field. */
        MISSING
    }

    /** Result of the whole entry-condition set. */
    public enum OverallResult {
        SATISFIED,
        NOT_SATISFIED,
        INDETERMINATE
    }

    /** How conditions combine: NONE, AND, OR, CUSTOM or FORMULA. */
    @AuraEnabled
    public String logicType { get; set; }
    /** Combined result for the current record values. Lightning components read overallCode instead. */
    public OverallResult overall {
        get;
        set {
            overall = value;
            overallCode = value?.name();
        }
    }
    /** Overall result name for Lightning components (Apex enums arrive empty there), e.g. NOT_SATISFIED. */
    @AuraEnabled
    public String overallCode { get; set; }
    /** Why the overall result is what it is. */
    @AuraEnabled
    public String overallReason { get; set; }
    /** One entry per condition, in metadata order. */
    @AuraEnabled
    public List<ConditionResult> conditions { get; set; }

    /**
     * Creates an empty result.
     */
    public FlowProofEvaluationResult() {
        this.conditions = new List<ConditionResult>();
    }

    /**
     * Result for one condition, with display strings for the UI.
     */
    public with sharing class ConditionResult {
        /** 1-based condition number. */
        @AuraEnabled
        public Integer index { get; set; }
        /** Field API name. */
        @AuraEnabled
        public String field { get; set; }
        /** FlowRecordFilterOperator name. */
        @AuraEnabled
        public String operator { get; set; }
        /** Comparison value rendered for display. */
        @AuraEnabled
        public String expectedDisplay { get; set; }
        /** Record value rendered for display; never set for inaccessible fields. */
        @AuraEnabled
        public String actualDisplay { get; set; }
        /** Evaluation outcome. Lightning components read outcomeCode instead. */
        public ConditionOutcome outcome {
            get;
            set {
                outcome = value;
                outcomeCode = value?.name();
            }
        }
        /** Outcome name for Lightning components (Apex enums arrive empty there), e.g. NO_MATCH. */
        @AuraEnabled
        public String outcomeCode { get; set; }
        /** Explanation of the outcome, including any assumption made. */
        @AuraEnabled
        public String reason { get; set; }

        /**
         * Sets the outcome and its explanation.
         * @param outcome evaluation outcome
         * @param reason explanation shown to the user
         * @return this result, for chaining
         */
        public ConditionResult resolve(ConditionOutcome outcome, String reason) {
            this.outcome = outcome;
            this.reason = reason;
            return this;
        }
    }
}
