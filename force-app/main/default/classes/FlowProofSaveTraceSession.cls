/**
 * A running "Record a test save": which record is being watched, since when, and the debug-log
 * trace flag FlowProof switched on for the user (so it can be switched off or restored afterwards).
 */
public with sharing class FlowProofSaveTraceSession {
    /** API name of the record's object. */
    @AuraEnabled
    public String objectApiName { get; set; }
    /** The watched record. */
    @AuraEnabled
    public Id recordId { get; set; }
    /** TraceFlag Id (Tooling API). */
    @AuraEnabled
    public String traceFlagId { get; set; }
    /** True when FlowProof created the trace flag; false when it reused the user's own. */
    @AuraEnabled
    public Boolean createdTraceFlag { get; set; }
    /** Debug level the user's own trace flag had before FlowProof changed it; null when created. */
    @AuraEnabled
    public String previousDebugLevelId { get; set; }
    /** When logging started; saves before this are ignored. */
    @AuraEnabled
    public Datetime startedAt { get; set; }
    /** When logging stops by itself. */
    @AuraEnabled
    public Datetime expiresAt { get; set; }
}
