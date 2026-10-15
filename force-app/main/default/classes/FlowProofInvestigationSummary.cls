/**
 * One row of the investigation history list.
 */
public with sharing class FlowProofInvestigationSummary {
    /** FlowProof_Investigation__c Id. */
    @AuraEnabled
    public Id investigationId { get; set; }
    /** Auto-number name, e.g. INV-0001. */
    @AuraEnabled
    public String name { get; set; }
    /** API name of the investigated record's object. */
    @AuraEnabled
    public String objectApiName { get; set; }
    /** The investigated record. */
    @AuraEnabled
    public String recordId { get; set; }
    /** Flow label at the time of the investigation. */
    @AuraEnabled
    public String flowLabel { get; set; }
    /** SATISFIED, NOT_SATISFIED, INDETERMINATE or NOT_EVALUATED. */
    @AuraEnabled
    public String overallResult { get; set; }
    /** Title of the most important finding. */
    @AuraEnabled
    public String topFinding { get; set; }
    /** Number of findings. */
    @AuraEnabled
    public Integer findingCount { get; set; }
    /** When the investigation ran. */
    @AuraEnabled
    public Datetime createdDate { get; set; }
}
