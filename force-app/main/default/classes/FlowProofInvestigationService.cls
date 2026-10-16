/**
 * Runs investigations: reads a Flow's settings, entry conditions and full definition, reads the
 * referenced fields of the record with the user's permissions, evaluates the conditions, diagnoses
 * the result and runs the Flow health checks. Failing to read a Flow definition does not fail the
 * investigation; it becomes an INSUFFICIENT_EVIDENCE finding. Makes callouts and performs no DML,
 * so callers can save the result afterwards in the same transaction.
 *
 * @example
 * FlowProofInvestigationResult result = new FlowProofInvestigationService()
 *     .investigate(new FlowProofInvestigationRequest('Opportunity', opportunityId, 'Opportunity_Onboarding'));
 * FlowProofSweepResult sweep = new FlowProofInvestigationService().checkAllFlows('Opportunity', opportunityId);
 */
public with sharing class FlowProofInvestigationService {
    /** Most Flows one "check all Flows" run reads (one org API callout each). */
    @TestVisible
    private static final Integer MAX_SWEEP_FLOWS = 30;
    // Stops starting new callouts well before Salesforce's 120-second callout limit per transaction.
    private static final Long SWEEP_TIME_BUDGET_MS = 90000;

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
     * @param definitions source of Flow definitions
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
        FlowProofInvestigationResult result = newResult(
            request.objectApiName,
            request.recordId,
            catalog.getFlow(request.flowApiName)
        );
        result.expectedOutcome = request.expectedOutcome;
        FlowProofDiagnosticContext context = prepare(result, null);
        FlowProofRecordSnapshot snapshot = context.isSameObject()
            ? records.getSnapshot(request.objectApiName, request.recordId, referencedFields(context.start))
            : null;
        finish(context, result, snapshot);
        return result;
    }

    /**
     * Checks every record-triggered Flow on the record's object against the record in one pass: one
     * definition read per Flow (active Flows first, at most MAX_SWEEP_FLOWS) and one read of the record.
     * @param objectApiName API name of the record's object
     * @param recordId the record
     * @return one row per checked Flow, in catalog order
     * @throws IllegalArgumentException when the object or record is missing
     * @throws FlowProofException when the Flows or the record cannot be read with the user's permissions
     */
    public FlowProofSweepResult checkAllFlows(String objectApiName, Id recordId) {
        return checkAllFlows(objectApiName, recordId, null);
    }

    /**
     * Like checkAllFlows, but compares the Flows with simulated values for some fields ("what if").
     * The record is never changed: only the in-memory copy of its values is.
     * @param objectApiName API name of the record's object
     * @param recordId the record
     * @param whatIfValues simulated values by field API name (blank means blank); null or empty for a real check
     * @return one row per checked Flow; simulated and simulatedChanges say what was changed
     * @throws IllegalArgumentException when the object or record is missing, or a simulated value is invalid
     * @throws FlowProofException when the Flows or the record cannot be read with the user's permissions
     */
    public FlowProofSweepResult checkAllFlows(String objectApiName, Id recordId, Map<String, String> whatIfValues) {
        if (String.isBlank(objectApiName) || recordId == null) {
            throw new IllegalArgumentException('Choose an object and a record to check.');
        }
        // Reading the record first fails fast, before any callout, when the user cannot see it.
        FlowProofRecordSnapshot access = records.getSnapshot(objectApiName, recordId, new Set<String>());
        List<FlowProofFlowSummary> flows = catalog.listRecordTriggeredFlows(objectApiName);

        FlowProofSweepResult sweep = new FlowProofSweepResult();
        sweep.objectApiName = objectApiName;
        sweep.recordId = recordId;
        sweep.recordName = access.recordName;
        sweep.flowCount = flows.size();

        List<FlowProofInvestigationResult> results = new List<FlowProofInvestigationResult>();
        List<FlowProofDiagnosticContext> contexts = new List<FlowProofDiagnosticContext>();
        Set<String> fields = new Set<String>();
        Long startedAt = System.currentTimeMillis();
        for (FlowProofFlowSummary flow : activeFirst(flows)) {
            if (results.size() >= MAX_SWEEP_FLOWS || System.currentTimeMillis() - startedAt > SWEEP_TIME_BUDGET_MS) {
                sweep.skippedFlowLabels.add(flow.label);
                continue;
            }
            FlowProofInvestigationResult result = newResult(objectApiName, recordId, flow);
            FlowProofDiagnosticContext context = prepare(result, flows);
            if (context.isSameObject()) {
                fields.addAll(referencedFields(context.start));
            }
            results.add(result);
            contexts.add(context);
        }

        FlowProofRecordSnapshot snapshot = fields.isEmpty()
            ? access
            : records.getSnapshot(objectApiName, recordId, fields);
        // Described before simulated values are applied, so the form shows the real current values.
        sweep.whatIfFields = records.describeWhatIfFields(snapshot);
        if (whatIfValues != null && !whatIfValues.isEmpty()) {
            sweep.simulated = true;
            sweep.simulatedChanges = FlowProofRecordService.applyWhatIfValues(snapshot, whatIfValues);
        }
        for (Integer i = 0; i < results.size(); i++) {
            finish(contexts[i], results[i], contexts[i].isSameObject() ? snapshot : null);
            sweep.rows.add(new FlowProofSweepRow(results[i]));
        }
        sweep.rows.sort();
        return sweep;
    }

    private static FlowProofInvestigationResult newResult(
        String objectApiName,
        Id recordId,
        FlowProofFlowSummary flow
    ) {
        FlowProofInvestigationResult result = new FlowProofInvestigationResult();
        result.objectApiName = objectApiName;
        result.recordId = recordId;
        result.flow = flow;
        result.investigatedAt = Datetime.now();
        return result;
    }

    /**
     * Reads the Flow's definition and runs the health checks; needs no record data.
     * @param objectFlows the Flows on the same object when already known, else null
     */
    private FlowProofDiagnosticContext prepare(
        FlowProofInvestigationResult result,
        List<FlowProofFlowSummary> objectFlows
    ) {
        FlowProofDiagnosticContext context = new FlowProofDiagnosticContext(result.objectApiName, result.flow);
        if (result.flow.isRecordTriggered != true) {
            return context;
        }
        FlowProofFlowDefinition definition = readDefinition(context, result);
        if (definition?.metadata != null) {
            result.healthFindings = new FlowProofFlowHealthAnalyzer()
                .analyze(definition, otherActiveFlowsAtSameTrigger(result.flow, context.start, objectFlows));
            result.healthChecked = true;
        }
        return context;
    }

    /** Evaluates the conditions against the record (when given) and diagnoses the result. */
    private static void finish(
        FlowProofDiagnosticContext context,
        FlowProofInvestigationResult result,
        FlowProofRecordSnapshot snapshot
    ) {
        if (snapshot != null) {
            context.evaluation = new FlowProofConditionEvaluator().evaluate(context.start, snapshot);
            result.evaluation = context.evaluation;
            result.recordName = snapshot.recordName;
        }
        result.findings = new FlowProofDiagnosticEngine().diagnose(context);
    }

    private FlowProofFlowDefinition readDefinition(
        FlowProofDiagnosticContext context,
        FlowProofInvestigationResult result
    ) {
        String versionId = String.isNotBlank(result.flow.activeVersionId)
            ? result.flow.activeVersionId
            : result.flow.latestVersionId;
        if (String.isBlank(versionId)) {
            return null;
        }
        result.evaluatedVersionId = versionId;
        FlowProofFlowDefinition definition;
        try {
            definition = definitions.getDefinition(Id.valueOf(versionId));
        } catch (FlowProofMetadataException e) {
            context.metadataFailure = e.reason;
            context.metadataFailureMessage = e.getMessage();
            return null;
        } catch (FlowProofException e) {
            context.metadataFailure = FlowProofMetadataException.Reason.INVALID_RESPONSE;
            context.metadataFailureMessage = e.getMessage();
            return null;
        }
        context.start = definition.start;
        result.conditionsRead = true;
        result.triggerObject = context.start.objectApiName;
        result.recordTriggerType = context.start.recordTriggerType;
        result.runsOnlyWhenUpdatedToMeetConditions = context.start.requiresRecordChangedToMeetCriteria;
        return definition;
    }

    /**
     * @return how many other active Flows run at the same point on the same object, or null when this
     *         Flow is inactive or the other Flows cannot be listed
     */
    private Integer otherActiveFlowsAtSameTrigger(
        FlowProofFlowSummary flow,
        FlowProofFlowModel.FlowStart start,
        List<FlowProofFlowSummary> objectFlows
    ) {
        if (flow.isActive != true || String.isBlank(start?.objectApiName)) {
            return null;
        }
        List<FlowProofFlowSummary> peers = objectFlows;
        if (peers == null) {
            try {
                peers = catalog.listRecordTriggeredFlows(start.objectApiName);
            } catch (FlowProofException e) {
                return null;
            }
        }
        Integer count = 0;
        for (FlowProofFlowSummary peer : peers) {
            if (peer.isActive == true && peer.apiName != flow.apiName && peer.triggerType == start.triggerType) {
                count++;
            }
        }
        return count;
    }

    private static List<FlowProofFlowSummary> activeFirst(List<FlowProofFlowSummary> flows) {
        List<FlowProofFlowSummary> ordered = new List<FlowProofFlowSummary>();
        List<FlowProofFlowSummary> inactive = new List<FlowProofFlowSummary>();
        for (FlowProofFlowSummary flow : flows) {
            if (flow.isActive == true) {
                ordered.add(flow);
            } else {
                inactive.add(flow);
            }
        }
        ordered.addAll(inactive);
        return ordered;
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
