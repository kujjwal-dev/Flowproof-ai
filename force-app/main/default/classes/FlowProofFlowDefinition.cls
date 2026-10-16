/**
 * One Flow version as read from the org: its parsed start element (trigger settings and entry
 * conditions) and its full metadata, which the health checks walk (loops, record operations,
 * fault paths). Metadata may be null when a source only provides the start element.
 */
public with sharing class FlowProofFlowDefinition {
    /** Parsed start element. */
    public FlowProofFlowModel.FlowStart start { get; private set; }
    /** Full Flow metadata as untyped JSON (Tooling API Flow.Metadata); may be null. */
    public Map<String, Object> metadata { get; private set; }

    /**
     * @param start parsed start element
     * @param metadata full Flow metadata, or null
     */
    public FlowProofFlowDefinition(FlowProofFlowModel.FlowStart start, Map<String, Object> metadata) {
        this.start = start;
        this.metadata = metadata;
    }
}
