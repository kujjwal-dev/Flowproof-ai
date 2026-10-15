/**
 * Supplies the start element (trigger settings and entry conditions) of a specific Flow version.
 * Implementations: FlowProofToolingFlowSource (live, through the org's Tooling API); tests use stubs.
 */
public interface FlowProofFlowDefinitionSource {
    /**
     * @param flowVersionId Id of the Flow version (key prefix 301), usually FlowDefinitionView.ActiveVersionId
     * @return the parsed start element
     * @throws FlowProofMetadataException when the definition cannot be read; the reason says why
     */
    FlowProofFlowModel.FlowStart getStart(Id flowVersionId);
}
