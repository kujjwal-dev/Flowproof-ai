/**
 * An object that has record-triggered Flows, for the New Investigation object picker.
 * Sorts by label.
 */
public with sharing class FlowProofObjectOption implements Comparable {
    /** Object API name, e.g. Opportunity. */
    @AuraEnabled
    public String apiName { get; set; }
    /** Object label. */
    @AuraEnabled
    public String label { get; set; }
    /** Number of record-triggered Flows on the object (any activation state). */
    @AuraEnabled
    public Integer flowCount { get; set; }

    /**
     * @param apiName object API name
     * @param label object label
     * @param flowCount number of record-triggered Flows
     */
    public FlowProofObjectOption(String apiName, String label, Integer flowCount) {
        this.apiName = apiName;
        this.label = label;
        this.flowCount = flowCount;
    }

    /**
     * Orders by label, case-insensitively.
     * @param other another FlowProofObjectOption
     * @return negative, zero or positive
     */
    public Integer compareTo(Object other) {
        return (label ?? '').toLowerCase().compareTo((((FlowProofObjectOption) other).label ?? '').toLowerCase());
    }
}
