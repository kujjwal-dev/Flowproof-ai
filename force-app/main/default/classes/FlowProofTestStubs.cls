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
        return opportunityFlow(apiName, true);
    }

    /**
     * A FlowDefinitionView row for a record-triggered after-save Flow on Opportunity.
     * @param apiName Flow API name
     * @param isActive true for an active Flow; an inactive one has only a latest version
     * @return the row (built through JSON because its fields are read-only)
     */
    public static FlowDefinitionView opportunityFlow(String apiName, Boolean isActive) {
        return (FlowDefinitionView) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'FlowDefinitionView' },
                    'ApiName' => apiName,
                    'Label' => apiName.replace('_', ' '),
                    'IsActive' => isActive,
                    'ActiveVersionId' => isActive ? VERSION_ID : null,
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
     * @param apiName object API name
     * @return an EntityDefinition row whose DurableId is the API name
     */
    public static EntityDefinition entity(String apiName) {
        return (EntityDefinition) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'EntityDefinition' },
                    'DurableId' => apiName,
                    'QualifiedApiName' => apiName
                }
            ),
            EntityDefinition.class
        );
    }

    /**
     * Full metadata of an after-save Flow on Opportunity with one Create Records element and no
     * fault path, which the health checks report.
     * @return untyped Flow metadata
     */
    public static Map<String, Object> metadataWithoutFaultPath() {
        return new Map<String, Object>{
            'label' => 'Opportunity Onboarding',
            'start' => new Map<String, Object>{
                'object' => 'Opportunity',
                'triggerType' => 'RecordAfterSave',
                'recordTriggerType' => 'CreateAndUpdate',
                'doesRequireRecordChangedToMeetCriteria' => true,
                'connector' => new Map<String, Object>{ 'targetReference' => 'Create_Task' }
            },
            'recordCreates' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Create_Task', 'label' => 'Create Task', 'object' => 'Task' }
            }
        };
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
        queries.entities.add(entity('Opportunity'));
        return new FlowProofInvestigationService(
            new FlowProofFlowCatalogService(queries),
            new Definitions(start),
            new FlowProofRecordService()
        );
    }

    /**
     * Creates an Opportunity and investigates it against the onboarding conditions (stubbed Flow
     * metadata, no callouts). The result is not saved.
     * @param name Opportunity name
     * @param stageName stage
     * @param amount amount
     * @return the unsaved result
     */
    public static FlowProofInvestigationResult investigateOpportunity(String name, String stageName, Decimal amount) {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(name, stageName, amount, true);
        return investigationService(activeOpportunityFlow('Opportunity_Onboarding'), onboardingStart())
            .investigate(new FlowProofInvestigationRequest('Opportunity', opportunity.Id, 'Opportunity_Onboarding'));
    }

    /**
     * @param enabled whether AI explanations are on
     * @return settings for the default Gemini model, with field values not shared
     */
    public static FlowProofSettings aiSettings(Boolean enabled) {
        FlowProofSettings settings = new FlowProofSettings();
        settings.aiEnabled = enabled;
        settings.aiModel = 'gemini-3.8-flash';
        settings.aiSendFieldValues = false;
        return settings;
    }

    /**
     * @param answerText the model's answer
     * @return a generateContent response body with one finished candidate
     */
    public static String geminiResponse(String answerText) {
        return JSON.serialize(
            new Map<String, Object>{
                'candidates' => new List<Object>{
                    new Map<String, Object>{
                        'finishReason' => 'STOP',
                        'content' => new Map<String, Object>{
                            'role' => 'model',
                            'parts' => new List<Object>{ new Map<String, Object>{ 'text' => answerText } }
                        }
                    }
                }
            }
        );
    }

    /**
     * @return a valid explanation answer citing the failing-conditions finding and condition 3
     */
    public static String geminiAnswer() {
        return JSON.serialize(
            new Map<String, Object>{
                'summary' => 'The Flow did not act because the Type condition is not met.',
                'keyPoints' => new List<Object>{
                    new Map<String, Object>{
                        'text' => 'Type must be New Customer.',
                        'basedOn' => new List<String>{ 'CONDITIONS_NOT_MET', 'C3' }
                    }
                },
                'nextSteps' => new List<String>{ 'Set Type to New Customer if that is correct for this deal.' },
                'caveats' => new List<String>{ 'Whether the Flow ran at the last save is not confirmed.' }
            }
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

    /** Definition source stub returning a fixed start element and optional full metadata. */
    public class Definitions implements FlowProofFlowDefinitionSource {
        private final FlowProofFlowModel.FlowStart start;
        /** Full metadata to return (for health checks); null by default. */
        public Map<String, Object> metadata;
        /** Version Ids requested, in order. */
        public List<String> requestedVersionIds = new List<String>();

        /**
         * @param start the start element to return
         */
        public Definitions(FlowProofFlowModel.FlowStart start) {
            this.start = start;
        }

        public FlowProofFlowDefinition getDefinition(Id flowVersionId) {
            requestedVersionIds.add(flowVersionId);
            return new FlowProofFlowDefinition(start, metadata);
        }
    }

    /** HTTP mock returning a fixed status and body; records the requests it answers. */
    public class FixedResponse implements HttpCalloutMock {
        private final Integer status;
        private final String body;
        /** Requests answered, in order. */
        public List<HttpRequest> requests = new List<HttpRequest>();

        /**
         * @param status HTTP status to return
         * @param body body to return
         */
        public FixedResponse(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            response.setBody(body);
            return response;
        }
    }
}
