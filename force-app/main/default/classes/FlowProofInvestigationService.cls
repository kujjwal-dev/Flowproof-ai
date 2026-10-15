/**
 * Runs one investigation: reads the Flow's settings and entry conditions, reads the referenced
 * fields of the record with the user's permissions, evaluates the conditions and diagnoses the
 * result. Failing to read the Flow definition does not fail the investigation; it becomes an
 * INSUFFICIENT_EVIDENCE finding. Makes a callout and performs no DML, so callers can save the
 * result afterwards in the same transaction.
 *
 * @example
 * FlowProofInvestigationResult result = new FlowProofInvestigationService()
 *     .investigate(new FlowProofInvestigationRequest('Opportunity', opportunityId, 'Opportunity_Onboarding'));
 */
public with sharing class FlowProofInvestigationService {
    private final FlowProofFlowCatalogService catalog;
    private final FlowProofFlowDefinitionSource definitions;
    private final FlowProofRecordService records;

    /**
     * Creates a service that reads Flow definitions through the org's Tooling API.
     */
    public FlowProofInvestigationService() {
        this(new FlowProofFlowCatalogService(), new FlowProofToolingFlowSource(), new FlowProofRecordService());
    }

    /**
     * @param catalog Flow catalog
     * @param definitions source of Flow start elements
     * @param records record reader
     */
    @TestVisible
    private FlowProofInvestigationService(
        FlowProofFlowCatalogService catalog,
        FlowProofFlowDefinitionSource definitions,
        FlowProofRecordService records
    ) {
        this.catalog = catalog;
        this.definitions = definitions;
        this.records = records;
    }

    /**
     * Investigates why a Flow did or did not act on a record.
     * @param request the record and the Flow
     * @return the result, not yet saved
     * @throws IllegalArgumentException when the request is incomplete
     * @throws FlowProofException when the Flow or the record cannot be read with the user's permissions
     */
    public FlowProofInvestigationResult investigate(FlowProofInvestigationRequest request) {
        if (
            request == null ||
            String.isBlank(request.objectApiName) ||
            request.recordId == null ||
            String.isBlank(request.flowApiName)
        ) {
            throw new IllegalArgumentException('Choose an object, a record and a Flow to investigate.');
        }
        FlowProofInvestigationResult result = new FlowProofInvestigationResult();
        result.objectApiName = request.objectApiName;
        result.recordId = request.recordId;
        result.expectedOutcome = request.expectedOutcome;
        result.investigatedAt = Datetime.now();
        result.flow = catalog.getFlow(request.flowApiName);

        FlowProofDiagnosticContext context = new FlowProofDiagnosticContext(request.objectApiName, result.flow);
        if (result.flow.isRecordTriggered == true) {
            readStart(context, result);
        }
        if (context.isSameObject()) {
            Set<String> fields = referencedFields(context.start);
            FlowProofRecordSnapshot snapshot = records.getSnapshot(request.objectApiName, request.recordId, fields);
            context.evaluation = new FlowProofConditionEvaluator().evaluate(context.start, snapshot);
            result.evaluation = context.evaluation;
        }
        result.findings = new FlowProofDiagnosticEngine().diagnose(context);
        return result;
    }

    private void readStart(FlowProofDiagnosticContext context, FlowProofInvestigationResult result) {
        String versionId = String.isNotBlank(result.flow.activeVersionId)
            ? result.flow.activeVersionId
            : result.flow.latestVersionId;
        if (String.isBlank(versionId)) {
            return;
        }
        result.evaluatedVersionId = versionId;
        try {
            context.start = definitions.getStart(Id.valueOf(versionId));
        } catch (FlowProofMetadataException e) {
            context.metadataFailure = e.reason;
            context.metadataFailureMessage = e.getMessage();
            return;
        } catch (FlowProofException e) {
            context.metadataFailure = FlowProofMetadataException.Reason.INVALID_RESPONSE;
            context.metadataFailureMessage = e.getMessage();
            return;
        }
        result.conditionsRead = true;
        result.triggerObject = context.start.objectApiName;
        result.recordTriggerType = context.start.recordTriggerType;
        result.runsOnlyWhenUpdatedToMeetConditions = context.start.requiresRecordChangedToMeetCriteria;
    }

    private static Set<String> referencedFields(FlowProofFlowModel.FlowStart start) {
        Set<String> fields = new Set<String>();
        for (FlowProofFlowModel.Condition condition : start.filters) {
            if (String.isNotBlank(condition.field)) {
                fields.add(condition.field);
            }
        }
        return fields;
    }
}
