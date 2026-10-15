/**
 * Raised when a Flow definition cannot be read. The reason tells the investigation which
 * INSUFFICIENT_EVIDENCE finding and next step to report (for example, "authorize FlowProof").
 *
 * @example
 * throw new FlowProofMetadataException('Flow not found.').withReason(FlowProofMetadataException.Reason.NOT_FOUND);
 */
public with sharing class FlowProofMetadataException extends FlowProofException {
    /** Why the Flow definition could not be read. */
    public enum Reason {
        /** The named credential callout failed before any HTTP response (missing setup, timeout, network). */
        CONNECTION_FAILED,
        /** The org API rejected the user's token or permissions (401/403). */
        NOT_AUTHORIZED,
        /** No Flow version with that Id exists. */
        NOT_FOUND,
        /** The Flow exists but its metadata is hidden (for example, a managed-package Flow). */
        NO_METADATA,
        /** The response could not be understood. */
        INVALID_RESPONSE,
        /** The org API returned another error status. */
        UNAVAILABLE,
        /** Salesforce refused the callout because data was changed earlier in the same transaction. */
        CALLOUT_AFTER_DML
    }

    /** Why the definition could not be read; null only if never set. */
    public Reason reason { get; private set; }

    /**
     * Sets the reason. Apex exceptions cannot declare custom constructors, so this is a fluent setter.
     * @param reason why the Flow definition could not be read
     * @return this exception, for throwing
     */
    public FlowProofMetadataException withReason(Reason reason) {
        this.reason = reason;
        return this;
    }
}
