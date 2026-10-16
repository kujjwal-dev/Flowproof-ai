/**
 * The outcome of one "check all Flows" run: every record-triggered Flow on an object, checked
 * against one record's current values. Not saved; the user opens a full investigation from a row.
 * Deterministic: produced without AI.
 */
public with sharing class FlowProofSweepResult {
    /** API name of the record's object. */
    @AuraEnabled
    public String objectApiName { get; set; }
    /** The checked record. */
    @AuraEnabled
    public Id recordId { get; set; }
    /** The record's name, when the user can read it. */
    @AuraEnabled
    public String recordName { get; set; }
    /** Number of record-triggered Flows on the object, checked or not. */
    @AuraEnabled
    public Integer flowCount { get; set; }
    /** One row per checked Flow: active Flows first, then by label. */
    @AuraEnabled
    public List<FlowProofSweepRow> rows { get; set; }
    /** Labels of Flows not checked because the run reached its limit. */
    @AuraEnabled
    public List<String> skippedFlowLabels { get; set; }
    /** Always NOT_CONFIRMED: Salesforce keeps no per-record run history for record-triggered Flows. */
    @AuraEnabled
    public String historicalExecution { get; set; }
    /** When the check ran. */
    @AuraEnabled
    public Datetime checkedAt { get; set; }

    /**
     * Creates an empty result.
     */
    public FlowProofSweepResult() {
        this.flowCount = 0;
        this.rows = new List<FlowProofSweepRow>();
        this.skippedFlowLabels = new List<String>();
        this.historicalExecution = 'NOT_CONFIRMED';
        this.checkedAt = Datetime.now();
    }
}
