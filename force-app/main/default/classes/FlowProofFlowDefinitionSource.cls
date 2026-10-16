/**
 * Supplies one Flow version's definition: its start element and, when available, its full metadata.
 * Implementations: FlowProofToolingFlowSource (live, through the org's Tooling API); tests use stubs.
 */
public interface FlowProofFlowDefinitionSource {
    /**
     * @param flowVersionId Id of the Flow version (key prefix 301), usually FlowDefinitionView.ActiveVersionId
     * @return the parsed definition
     * @throws FlowProofMetadataException when the definition cannot be read; the reason says why
     */
    FlowProofFlowDefinition getDefinition(Id flowVersionId);
}
