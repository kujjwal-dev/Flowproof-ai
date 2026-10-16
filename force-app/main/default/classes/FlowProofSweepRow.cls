/**
 * One Flow in a "check all Flows" result: whether its entry conditions match the record's current
 * values, its most important finding, and its health summary. Rows sort active Flows first, then
 * by label.
 */
public with sharing class FlowProofSweepRow implements Comparable {
    /** Flow API name; used to open a full investigation. */
    @AuraEnabled
    public String flowApiName { get; set; }
    /** Flow label. */
    @AuraEnabled
    public String flowLabel { get; set; }
    /** True when the Flow has an active version. */
    @AuraEnabled
    public Boolean isActive { get; set; }
    /** RecordBeforeSave, RecordAfterSave or RecordBeforeDelete. */
    @AuraEnabled
    public String triggerType { get; set; }
    /** Create, Update, CreateAndUpdate or Delete. */
    @AuraEnabled
    public String recordTriggerType { get; set; }
    /** True when the Flow's entry conditions were read. */
    @AuraEnabled
    public Boolean conditionsRead { get; set; }
    /** True when the Flow runs only when a record is updated to meet the conditions. */
    @AuraEnabled
    public Boolean runsOnlyWhenUpdatedToMeetConditions { get; set; }
    /** SATISFIED, NOT_SATISFIED, INDETERMINATE or NOT_EVALUATED. */
    @AuraEnabled
    public String overallCode { get; set; }
    /** Conditions that did not match the record's current values, or could not be checked. */
    @AuraEnabled
    public List<FlowProofEvaluationResult.ConditionResult> unmatchedConditions { get; set; }
    /** The most important diagnostic finding; null when there is none. */
    @AuraEnabled
    public FlowProofFinding topFinding { get; set; }
    /** Number of diagnostic findings. */
    @AuraEnabled
    public Integer findingCount { get; set; }
    /** True when the Flow's health checks ran. */
    @AuraEnabled
    public Boolean healthChecked { get; set; }
    /** Number of health findings. */
    @AuraEnabled
    public Integer healthCount { get; set; }
    /** The most important health finding; null when there is none. */
    @AuraEnabled
    public FlowProofFinding topHealthFinding { get; set; }

    /**
     * @param result an unsaved investigation result for one Flow
     */
    public FlowProofSweepRow(FlowProofInvestigationResult result) {
        this.flowApiName = result.flow.apiName;
        this.flowLabel = result.flow.label;
        this.isActive = result.flow.isActive == true;
        this.triggerType = result.flow.triggerType;
        this.recordTriggerType = result.recordTriggerType ?? result.flow.recordTriggerType;
        this.conditionsRead = result.conditionsRead == true;
        this.runsOnlyWhenUpdatedToMeetConditions = result.runsOnlyWhenUpdatedToMeetConditions == true;
        this.overallCode = result.evaluation?.overallCode ?? 'NOT_EVALUATED';
        this.unmatchedConditions = new List<FlowProofEvaluationResult.ConditionResult>();
        if (result.evaluation != null) {
            for (FlowProofEvaluationResult.ConditionResult condition : result.evaluation.conditions) {
                if (condition.outcome != FlowProofEvaluationResult.ConditionOutcome.MATCH) {
                    this.unmatchedConditions.add(condition);
                }
            }
        }
        this.findingCount = result.findings.size();
        this.topFinding = result.findings.isEmpty() ? null : result.findings[0];
        this.healthChecked = result.healthChecked == true;
        this.healthCount = result.healthFindings.size();
        this.topHealthFinding = result.healthFindings.isEmpty() ? null : result.healthFindings[0];
    }

    /**
     * Orders active Flows first, then by label.
     * @param other another FlowProofSweepRow
     * @return negative, zero or positive
     */
    public Integer compareTo(Object other) {
        FlowProofSweepRow that = (FlowProofSweepRow) other;
        if (this.isActive != that.isActive) {
            return this.isActive ? -1 : 1;
        }
        return (this.flowLabel ?? '').compareTo(that.flowLabel ?? '');
    }
}
