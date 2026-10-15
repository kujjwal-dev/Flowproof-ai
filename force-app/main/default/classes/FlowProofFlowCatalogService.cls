/**
 * Finds Flows and their activation and trigger settings through FlowDefinitionView,
 * which ordinary SOQL can read (unlike entry conditions). Queries run in user mode.
 *
 * @example
 * List<FlowProofFlowSummary> flows = new FlowProofFlowCatalogService().listRecordTriggeredFlows('Opportunity');
 */
public with sharing class FlowProofFlowCatalogService {
    private static final Set<String> RECORD_TRIGGER_TYPES = new Set<String>{
        'RecordBeforeSave',
        'RecordAfterSave',
        'RecordBeforeDelete'
    };
    private static final String NO_ACCESS_MESSAGE = 'You do not have permission to view Flow definitions. Ask an admin for the View Setup and Configuration permission.';

    private final FlowQueries queries;

    /**
     * Creates a service that queries the org.
     */
    public FlowProofFlowCatalogService() {
        this(new FlowQueries());
    }

    /**
     * @param queries query layer (replaced by a stub in tests)
     */
    @TestVisible
    private FlowProofFlowCatalogService(FlowQueries queries) {
        this.queries = queries;
    }

    /**
     * Lists the record-triggered Flows (any activation state) on an object, ordered by API name.
     * @param objectApiName API name of the object, e.g. Opportunity or Invoice__c
     * @return the Flows; empty when the object has none or does not exist
     * @throws IllegalArgumentException when objectApiName is blank
     * @throws FlowProofException when the user cannot view Flow definitions
     */
    public List<FlowProofFlowSummary> listRecordTriggeredFlows(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new IllegalArgumentException('An object API name is required.');
        }
        List<FlowProofFlowSummary> summaries = new List<FlowProofFlowSummary>();
        try {
            List<EntityDefinition> entities = queries.findEntity(objectApiName);
            if (entities.isEmpty()) {
                return summaries;
            }
            for (FlowDefinitionView view : queries.findRecordTriggeredFlows(entities[0].DurableId)) {
                summaries.add(toSummary(view));
            }
        } catch (QueryException e) {
            throw new FlowProofException(NO_ACCESS_MESSAGE, e);
        }
        return summaries;
    }

    /**
     * Reads one Flow's activation and trigger settings.
     * @param flowApiName Flow API name
     * @return the Flow summary
     * @throws IllegalArgumentException when flowApiName is blank
     * @throws FlowProofException when the Flow does not exist or the user cannot view Flow definitions
     */
    public FlowProofFlowSummary getFlow(String flowApiName) {
        if (String.isBlank(flowApiName)) {
            throw new IllegalArgumentException('A Flow API name is required.');
        }
        List<FlowDefinitionView> views;
        try {
            views = queries.findFlowByApiName(flowApiName);
        } catch (QueryException e) {
            throw new FlowProofException(NO_ACCESS_MESSAGE, e);
        }
        if (views.isEmpty()) {
            throw new FlowProofException(
                'No Flow named ' + flowApiName + ' was found, or you do not have access to it.'
            );
        }
        return toSummary(views[0]);
    }

    private static FlowProofFlowSummary toSummary(FlowDefinitionView view) {
        FlowProofFlowSummary summary = new FlowProofFlowSummary();
        summary.apiName = view.ApiName;
        summary.label = view.Label;
        summary.isActive = view.IsActive;
        summary.activeVersionId = view.ActiveVersionId;
        summary.latestVersionId = view.LatestVersionId;
        summary.processType = view.ProcessType;
        summary.triggerType = view.TriggerType;
        summary.recordTriggerType = view.RecordTriggerType;
        summary.triggerOrder = view.TriggerOrder;
        summary.triggerObjectLabel = view.TriggerObjectOrEventLabel;
        summary.isRecordTriggered = RECORD_TRIGGER_TYPES.contains(view.TriggerType);
        return summary;
    }

    /**
     * SOQL for the catalog. Inherits the caller's sharing; every query runs in user mode.
     */
    public virtual inherited sharing class FlowQueries {
        /**
         * @param objectApiName object API name
         * @return the matching EntityDefinition (at most one)
         */
        public virtual List<EntityDefinition> findEntity(String objectApiName) {
            return [
                SELECT DurableId, QualifiedApiName
                FROM EntityDefinition
                WHERE QualifiedApiName = :objectApiName
                WITH USER_MODE
                LIMIT 1
            ];
        }

        /**
         * @param triggerObjectDurableId EntityDefinition.DurableId of the triggering object
         * @return record-triggered Flow definitions on that object
         */
        public virtual List<FlowDefinitionView> findRecordTriggeredFlows(String triggerObjectDurableId) {
            return [
                SELECT
                    ApiName,
                    Label,
                    IsActive,
                    ActiveVersionId,
                    LatestVersionId,
                    ProcessType,
                    TriggerType,
                    RecordTriggerType,
                    TriggerOrder,
                    TriggerObjectOrEventLabel
                FROM FlowDefinitionView
                WHERE TriggerObjectOrEventId = :triggerObjectDurableId AND TriggerType IN :RECORD_TRIGGER_TYPES
                WITH USER_MODE
                ORDER BY ApiName
                LIMIT 200
            ];
        }

        /**
         * @param flowApiName Flow API name
         * @return the matching Flow definition (at most one)
         */
        public virtual List<FlowDefinitionView> findFlowByApiName(String flowApiName) {
            return [
                SELECT
                    ApiName,
                    Label,
                    IsActive,
                    ActiveVersionId,
                    LatestVersionId,
                    ProcessType,
                    TriggerType,
                    RecordTriggerType,
                    TriggerOrder,
                    TriggerObjectOrEventLabel
                FROM FlowDefinitionView
                WHERE ApiName = :flowApiName
                WITH USER_MODE
                LIMIT 1
            ];
        }
    }
}
