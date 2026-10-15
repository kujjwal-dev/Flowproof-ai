/**
 * Everything the diagnostic engine knows about one investigation. Fields that could not be
 * determined stay null (for example, start is null when the Flow definition could not be read).
 */
public with sharing class FlowProofDiagnosticContext {
    /** API name of the investigated record's object. */
    public String recordObjectApiName { get; set; }
    /** Activation and trigger settings of the Flow. */
    public FlowProofFlowSummary flow { get; set; }
    /** The Flow's start element; null when it was not read. */
    public FlowProofFlowModel.FlowStart start { get; set; }
    /** Why the start element could not be read; null when it was read or not attempted. */
    public FlowProofMetadataException.Reason metadataFailure { get; set; }
    /** User-safe explanation of the metadata failure. */
    public String metadataFailureMessage { get; set; }
    /** Entry-condition evaluation; null when conditions were not evaluated. */
    public FlowProofEvaluationResult evaluation { get; set; }

    /**
     * @param recordObjectApiName API name of the investigated record's object
     * @param flow the Flow's summary
     */
    public FlowProofDiagnosticContext(String recordObjectApiName, FlowProofFlowSummary flow) {
        this.recordObjectApiName = recordObjectApiName;
        this.flow = flow;
    }

    /**
     * @return true when the Flow's trigger object is the investigated record's object (case-insensitive)
     */
    public Boolean isSameObject() {
        return start != null &&
            String.isNotBlank(start.objectApiName) &&
            start.objectApiName.equalsIgnoreCase(recordObjectApiName);
    }
}
