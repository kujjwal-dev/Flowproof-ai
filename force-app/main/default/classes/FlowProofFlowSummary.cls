/**
 * Activation and trigger settings of one Flow definition, from FlowDefinitionView.
 * Contains no entry conditions; those come from a FlowProofFlowDefinitionSource.
 */
public with sharing class FlowProofFlowSummary {
    /** Flow API name. */
    @AuraEnabled
    public String apiName { get; set; }
    /** Flow label. */
    @AuraEnabled
    public String label { get; set; }
    /** True when the latest version is the active version (FlowDefinitionView.IsActive). */
    @AuraEnabled
    public Boolean isActive { get; set; }
    /** Id of the active version, or null when no version is active. */
    @AuraEnabled
    public String activeVersionId { get; set; }
    /** Id of the latest version, which may be a draft. */
    @AuraEnabled
    public String latestVersionId { get; set; }
    /** ProcessType, e.g. AutoLaunchedFlow. */
    @AuraEnabled
    public String processType { get; set; }
    /** RecordBeforeSave, RecordAfterSave, RecordBeforeDelete, Scheduled, PlatformEvent, ... */
    @AuraEnabled
    public String triggerType { get; set; }
    /** Create, Update, CreateAndUpdate, Delete. */
    @AuraEnabled
    public String recordTriggerType { get; set; }
    /** Trigger order (1-2000) when set. */
    @AuraEnabled
    public Integer triggerOrder { get; set; }
    /** Label of the triggering object or event. */
    @AuraEnabled
    public String triggerObjectLabel { get; set; }
    /** True for record-triggered Flows (before save, after save, before delete). */
    @AuraEnabled
    public Boolean isRecordTriggered { get; set; }
}
