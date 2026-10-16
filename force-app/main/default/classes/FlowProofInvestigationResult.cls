/**
 * The outcome of one investigation, as shown in the Results screen and stored (as JSON) on the
 * FlowProof_Investigation__c record. Deterministic: produced without AI.
 */
public with sharing class FlowProofInvestigationResult {
    /** Version of this JSON shape, for reading stored results later. */
    @AuraEnabled
    public Integer schemaVersion { get; set; }
    /** Id of the saved FlowProof_Investigation__c record; null until saved. */
    @AuraEnabled
    public Id investigationId { get; set; }
    /** Auto-number name of the saved record, e.g. INV-0001. */
    @AuraEnabled
    public String investigationName { get; set; }
    /** API name of the investigated record's object. */
    @AuraEnabled
    public String objectApiName { get; set; }
    /** The investigated record. */
    @AuraEnabled
    public Id recordId { get; set; }
    /** The record's name, when the user can read it. */
    @AuraEnabled
    public String recordName { get; set; }
    /** The user's description of the expected outcome, if given. */
    @AuraEnabled
    public String expectedOutcome { get; set; }
    /** The Flow's activation and trigger settings. */
    @AuraEnabled
    public FlowProofFlowSummary flow { get; set; }
    /** Id of the Flow version whose conditions were read (active, else latest). */
    @AuraEnabled
    public String evaluatedVersionId { get; set; }
    /** True when the Flow's entry conditions were read. */
    @AuraEnabled
    public Boolean conditionsRead { get; set; }
    /** Object the Flow is triggered by, from its definition. */
    @AuraEnabled
    public String triggerObject { get; set; }
    /** Create, Update, CreateAndUpdate or Delete, from the Flow's definition. */
    @AuraEnabled
    public String recordTriggerType { get; set; }
    /** True when the Flow runs only when a record is updated to meet the conditions. */
    @AuraEnabled
    public Boolean runsOnlyWhenUpdatedToMeetConditions { get; set; }
    /** Entry-condition evaluation against current values; null when not evaluated. */
    @AuraEnabled
    public FlowProofEvaluationResult evaluation { get; set; }
    /** Diagnostic findings, most important first. */
    @AuraEnabled
    public List<FlowProofFinding> findings { get; set; }
    /** True when the Flow's full definition was read and its health checks ran. */
    @AuraEnabled
    public Boolean healthChecked { get; set; }
    /** Flow health (best-practice) findings, most important first; suggestions only. */
    @AuraEnabled
    public List<FlowProofFinding> healthFindings { get; set; }
    /** Always NOT_CONFIRMED: Salesforce keeps no per-record run history for record-triggered Flows. */
    @AuraEnabled
    public String historicalExecution { get; set; }
    /** Optional Gemini explanation, stored separately from this deterministic result; null when none. */
    @AuraEnabled
    public FlowProofAiExplanation aiExplanation { get; set; }
    /** When the investigation ran. */
    @AuraEnabled
    public Datetime investigatedAt { get; set; }

    /**
     * Creates an empty result (also used for deserialization).
     */
    public FlowProofInvestigationResult() {
        this.schemaVersion = 2;
        this.conditionsRead = false;
        this.findings = new List<FlowProofFinding>();
        this.healthChecked = false;
        this.healthFindings = new List<FlowProofFinding>();
        this.historicalExecution = 'NOT_CONFIRMED';
    }
}
