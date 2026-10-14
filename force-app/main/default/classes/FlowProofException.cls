/**
 * Base exception for FlowProof failures that callers should report to the user as a
 * safe message (for example, unreadable Flow metadata). Virtual so that more specific
 * FlowProof exceptions can extend it when a caller needs to tell them apart.
 *
 * @example
 * throw new FlowProofException('Flow metadata is not valid JSON.', cause);
 */
public virtual with sharing class FlowProofException extends Exception {
}
