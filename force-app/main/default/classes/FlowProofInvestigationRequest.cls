/**
 * What the user asked FlowProof to investigate: one record and the Flow expected to act on it.
 */
public with sharing class FlowProofInvestigationRequest {
    /** API name of the record's object, e.g. Opportunity. */
    public String objectApiName { get; set; }
    /** The record. */
    public Id recordId { get; set; }
    /** API name of the Flow that was expected to act. */
    public String flowApiName { get; set; }
    /** Optional free-text description of the expected outcome (stored with the investigation). */
    public String expectedOutcome { get; set; }

    /**
     * No-arg constructor for deserialization.
     */
    public FlowProofInvestigationRequest() {
        this.objectApiName = null;
    }

    /**
     * @param objectApiName API name of the record's object
     * @param recordId the record
     * @param flowApiName API name of the Flow
     */
    public FlowProofInvestigationRequest(String objectApiName, Id recordId, String flowApiName) {
        this.objectApiName = objectApiName;
        this.recordId = recordId;
        this.flowApiName = flowApiName;
    }
}
