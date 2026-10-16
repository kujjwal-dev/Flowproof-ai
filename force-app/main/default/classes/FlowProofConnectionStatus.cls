/**
 * Result of testing a FlowProof connection (the org API or Gemini) for the current user.
 */
public with sharing class FlowProofConnectionStatus {
    /** True when the service answered successfully. */
    @AuraEnabled
    public Boolean connected { get; set; }
    /** CONNECTED, NOT_AUTHORIZED, NOT_CONFIGURED or UNAVAILABLE. */
    @AuraEnabled
    public String status { get; set; }
    /** What the status means and what to do about it. */
    @AuraEnabled
    public String message { get; set; }
    /** When the check ran. */
    @AuraEnabled
    public Datetime checkedAt { get; set; }

    /**
     * @param status status code
     * @param message user-facing explanation
     */
    public FlowProofConnectionStatus(String status, String message) {
        this.status = status;
        this.connected = status == 'CONNECTED';
        this.message = message;
        this.checkedAt = Datetime.now();
    }
}
