/**
 * Reusable test doubles for FlowProof tests: a Flow catalog query stub, a Flow definition stub
 * and an HTTP mock. Kept in one place so service and controller tests share them.
 */
@IsTest
public class FlowProofTestStubs {
    /** Built at runtime: a syntactically valid Flow version Id that exists in no org. */
    public static final String VERSION_ID = '301' + '0'.repeat(11) + '1AAA';

    /**
     * A FlowDefinitionView row for an active, record-triggered after-save Flow on Opportunity.
     * @param apiName Flow API name
     * @return the row (built through JSON because its fields are read-only)
     */
    public static FlowDefinitionView activeOpportunityFlow(String apiName) {
        return (FlowDefinitionView) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'FlowDefinitionView' },
                    'ApiName' => apiName,
                    'Label' => apiName.replace('_', ' '),
                    'IsActive' => true,
                    'ActiveVersionId' => VERSION_ID,
                    'LatestVersionId' => VERSION_ID,
                    'ProcessType' => 'AutoLaunchedFlow',
                    'TriggerType' => 'RecordAfterSave',
                    'RecordTriggerType' => 'CreateAndUpdate',
                    'TriggerObjectOrEventId' => 'Opportunity',
                    'TriggerObjectOrEventLabel' => 'Opportunity'
                }
            ),
            FlowDefinitionView.class
        );
    }

    /**
     * StageName = Closed Won AND Amount > 10000 AND Type = New Customer, after save on Opportunity.
     * @return the start element
     */
    public static FlowProofFlowModel.FlowStart onboardingStart() {
        FlowProofFlowModel.FlowStart start = new FlowProofFlowModel.FlowStart();
        start.objectApiName = 'Opportunity';
        start.triggerType = 'RecordAfterSave';
        start.recordTriggerType = 'CreateAndUpdate';
        start.filterLogic = 'and';
        start.filters.add(
            new FlowProofFlowModel.Condition(1, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won'))
        );
        start.filters.add(
            new FlowProofFlowModel.Condition(2, 'Amount', 'GreaterThan', FlowProofFlowModel.numberValue(10000))
        );
        start.filters.add(
            new FlowProofFlowModel.Condition(3, 'Type', 'EqualTo', FlowProofFlowModel.stringValue('New Customer'))
        );
        return start;
    }

    /**
     * An investigation service whose catalog returns one Flow and whose definition source returns the given start.
     * @param flow the Flow row the catalog returns
     * @param start the start element the definition source returns
     * @return the service (uses the real record service)
     */
    public static FlowProofInvestigationService investigationService(
        FlowDefinitionView flow,
        FlowProofFlowModel.FlowStart start
    ) {
        CatalogQueries queries = new CatalogQueries();
        queries.flows.add(flow);
        return new FlowProofInvestigationService(
            new FlowProofFlowCatalogService(queries),
            new Definitions(start),
            new FlowProofRecordService()
        );
    }

    /** Catalog query stub returning fixed rows. */
    public class CatalogQueries extends FlowProofFlowCatalogService.FlowQueries {
        /** Rows returned for every Flow query. */
        public List<FlowDefinitionView> flows = new List<FlowDefinitionView>();
        /** Rows returned for entity lookups. */
        public List<EntityDefinition> entities = new List<EntityDefinition>();

        public override List<FlowDefinitionView> findAllRecordTriggeredFlows() {
            return flows;
        }

        public override List<EntityDefinition> findEntitiesByDurableId(Set<String> durableIds) {
            return entities;
        }

        public override List<EntityDefinition> findEntity(String objectApiName) {
            return entities;
        }

        public override List<FlowDefinitionView> findRecordTriggeredFlows(String triggerObjectDurableId) {
            return flows;
        }

        public override List<FlowDefinitionView> findFlowByApiName(String flowApiName) {
            return flows;
        }
    }

    /** Definition source stub returning a fixed start element. */
    public class Definitions implements FlowProofFlowDefinitionSource {
        private final FlowProofFlowModel.FlowStart start;

        /**
         * @param start the start element to return
         */
        public Definitions(FlowProofFlowModel.FlowStart start) {
            this.start = start;
        }

        public FlowProofFlowModel.FlowStart getStart(Id flowVersionId) {
            return start;
        }
    }

    /** HTTP mock returning a fixed status and body. */
    public class FixedResponse implements HttpCalloutMock {
        private final Integer status;
        private final String body;

        /**
         * @param status HTTP status to return
         * @param body body to return
         */
        public FixedResponse(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            response.setBody(body);
            return response;
        }
    }
}
